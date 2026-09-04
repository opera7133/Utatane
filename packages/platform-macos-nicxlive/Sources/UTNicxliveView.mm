#import "UTNicxliveView.h"

#import <MetalKit/MetalKit.h>
#include <cmath>
#include <dlfcn.h>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

struct Vec2 { float x, y; };
struct Vec3 { float x, y, z; };
struct Mat4 { float values[4][4]; };
enum class Result : int { ok = 0 };
enum class CommandKind : uint32_t { drawPart };
struct RendererConfig { int width, height; };
struct FrameConfig { int width, height; };
struct ParameterUpdate { uint32_t uuid; Vec2 value; };
struct ParameterInfo {
    uint32_t uuid; bool isVec2; Vec2 min, max, defaults; const char *name;
    size_t nameLength; Vec2 value, latestInternal;
};
struct ParameterDescriptor { uint32_t uuid; bool isVec2; Vec2 min, max; };
struct ResourceCallbacks {
    void *userData;
    size_t (*createTexture)(int, int, int, int, int, bool, bool, void *);
    void (*updateTexture)(size_t, const uint8_t *, size_t, int, int, int, void *);
    void (*releaseTexture)(size_t, void *);
};
struct BufferSlice { const float *data; size_t length; };
struct SharedBuffers { BufferSlice vertices, uvs, deform; size_t vertexCount, uvCount, deformCount; };
struct PartPacket {
    bool isMask, renderable; Mat4 modelMatrix, renderMatrix; float renderRotation;
    Vec3 tint, screen; float opacity, emissionStrength, maskThreshold; int blendingMode;
    bool useMultistageBlend, hasEmissionOrBumpmap; size_t textures[3], textureCount;
    Vec2 origin; size_t vertexOffset, vertexStride, uvOffset, uvStride, deformOffset,
        deformStride, indexHandle; const uint16_t *indices; size_t indexCount, vertexCount;
};
struct MaskPacket {
    Mat4 modelMatrix, mvp; Vec2 origin; size_t vertexOffset, vertexStride,
        deformOffset, deformStride, indexHandle; const uint16_t *indices;
    size_t indexCount, vertexCount;
};
struct MaskApplyPacket { uint32_t kind; bool isDodge; PartPacket part; MaskPacket mask; };
struct DynamicPass {
    size_t textures[3], textureCount, stencil; Vec2 scale; float rotation;
    bool autoScaled; size_t originalBuffer; int originalViewport[4];
    int drawBufferCount; bool hasStencil;
};
struct QueuedCommand {
    CommandKind kind; PartPacket part; MaskApplyPacket maskApply;
    DynamicPass dynamic; bool usesStencil;
};
static_assert(sizeof(PartPacket) == 304, "nicxlive beta2 part ABI changed");
static_assert(sizeof(QueuedCommand) == 920, "nicxlive beta2 command ABI changed");
struct QueueView { const QueuedCommand *commands; size_t count; };

struct API {
    void *handle = nullptr;
    void (*runtimeInit)() = nullptr;
    void (*runtimeTerm)() = nullptr;
    Result (*createRenderer)(const RendererConfig *, const ResourceCallbacks *, void **) = nullptr;
    void (*destroyRenderer)(void *) = nullptr;
    Result (*loadPuppet)(void *, const char *, void **) = nullptr;
    Result (*unloadPuppet)(void *, void *) = nullptr;
    Result (*getParameters)(void *, ParameterInfo *, size_t, size_t *) = nullptr;
    Result (*updateParameters)(void *, const ParameterUpdate *, size_t) = nullptr;
    Result (*beginFrame)(void *, const FrameConfig *) = nullptr;
    Result (*tickPuppet)(void *, double) = nullptr;
    Result (*setPuppetScale)(void *, float, float) = nullptr;
    Result (*emitCommands)(void *, QueueView *) = nullptr;
    Result (*getSharedBuffers)(void *, SharedBuffers *) = nullptr;
    void (*flush)(void *) = nullptr;

    bool load(NSURL *url) {
        handle = dlopen(url.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!handle) return false;
#define LOAD(field, symbol) field = reinterpret_cast<decltype(field)>(dlsym(handle, symbol)); if (!field) return false
        LOAD(runtimeInit, "njgRuntimeInit"); LOAD(runtimeTerm, "njgRuntimeTerm");
        LOAD(createRenderer, "njgCreateRenderer"); LOAD(destroyRenderer, "njgDestroyRenderer");
        LOAD(loadPuppet, "njgLoadPuppet"); LOAD(unloadPuppet, "njgUnloadPuppet");
        LOAD(getParameters, "njgGetParameters"); LOAD(updateParameters, "njgUpdateParameters");
        LOAD(beginFrame, "njgBeginFrame"); LOAD(tickPuppet, "njgTickPuppet");
        LOAD(setPuppetScale, "njgSetPuppetScale");
        LOAD(emitCommands, "njgEmitCommands"); LOAD(getSharedBuffers, "njgGetSharedBuffers");
        LOAD(flush, "njgFlushCommandBuffer");
#undef LOAD
        return true;
    }
    ~API() { if (handle) dlclose(handle); }
};

struct TextureContext { id<MTLDevice> device; };
struct Vertex { Vec2 position, uv; };
size_t createTexture(int w,int h,int,int,int,bool,bool,void* user) {
    auto context=static_cast<TextureContext *>(user);
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
    return reinterpret_cast<size_t>((__bridge_retained void *)[context->device newTextureWithDescriptor:descriptor]);
}
void updateTexture(size_t h,const uint8_t*d,size_t,int w,int height,int c,void*) {
    id<MTLTexture> texture=(__bridge id<MTLTexture>)reinterpret_cast<void *>(h);
    std::vector<uint8_t> rgba;
    if(c!=4){rgba.resize((size_t)w*height*4);for(size_t i=0;i<(size_t)w*height;i++){rgba[i*4]=d[i*c];rgba[i*4+1]=c>1?d[i*c+1]:d[i*c];rgba[i*4+2]=c>2?d[i*c+2]:d[i*c];rgba[i*4+3]=255;}d=rgba.data();}
    [texture replaceRegion:MTLRegionMake2D(0,0,w,height) mipmapLevel:0 withBytes:d bytesPerRow:w*4];
}
void releaseTexture(size_t h,void*) { CFRelease(reinterpret_cast<CFTypeRef>(h)); }
void multiply(const Mat4&a,const Mat4&b,float out[16]) {
    for(int r=0;r<4;r++) for(int c=0;c<4;c++){ float v=0; for(int k=0;k<4;k++)v+=a.values[r][k]*b.values[k][c]; out[r*4+c]=v; }
}

} // namespace

@implementation UTNicxliveView {
    API *_api; void *_renderer; void *_puppet; uint32_t _roll, _breath, _blink;
    std::unordered_map<std::string, ParameterDescriptor> _parameters;
    std::unordered_map<uint32_t, Vec2> _parameterOverrides;
    TextureContext *_textureContext; id<MTLCommandQueue> _commandQueue; id<MTLRenderPipelineState> _pipeline; CFAbsoluteTime _started;
    CGFloat _contentOffsetX, _contentOffsetY;
    bool _isShuttingDown;
    bool _lastFrameHadVisiblePixels;
    bool _diagnosticsEnabled;
    bool _didLogFirstFrame;
    bool _didInspectFrame;
}

+ (instancetype)viewWithFrame:(NSRect)frame puppetURL:(NSURL *)puppetURL libraryURL:(NSURL *)libraryURL error:(NSError **)error {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!device){if(error)*error=[NSError errorWithDomain:@"UtataneNicxlive" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Metalデバイスを初期化できなかった"}];return nil;}
    UTNicxliveView *view=[[self alloc] initWithFrame:frame device:device];view->_diagnosticsEnabled=NSProcessInfo.processInfo.environment[@"UTATANE_NIJIGENERATE_DIAGNOSTICS"]!=nil;BOOL verifiesPixels=NSProcessInfo.processInfo.environment[@"UTATANE_NIJIGENERATE_VERIFY_PIXELS"]!=nil;view.delegate=view;view.colorPixelFormat=MTLPixelFormatBGRA8Unorm;view.clearColor=MTLClearColorMake(0,0,0,0);view.paused=NO;view.preferredFramesPerSecond=30;view.enableSetNeedsDisplay=NO;view.framebufferOnly=!(verifiesPixels||view->_diagnosticsEnabled);view.wantsLayer=YES;view.layer.opaque=NO;view.layer.backgroundColor=NSColor.clearColor.CGColor;view->_commandQueue=[device newCommandQueue];
    NSString *source=@"#include <metal_stdlib>\nusing namespace metal;struct V{float2 p,u;};struct O{float4 p[[position]];float2 u;};vertex O v(uint i[[vertex_id]],const device V*x[[buffer(0)]],constant float4*r[[buffer(1)]],constant float2&o[[buffer(2)]],constant float2&c[[buffer(3)]]){float4 p=float4(x[i].p-o,0,1);float4 q=float4(dot(r[0],p),dot(r[1],p),dot(r[2],p),dot(r[3],p));q.xy+=c*q.w;q.z=(q.z+q.w)*0.5;return{q,x[i].u};}fragment float4 f(O i[[stage_in]],texture2d<float>t[[texture(0)]],constant float&a[[buffer(0)]],constant float3&n[[buffer(1)]],constant float3&s[[buffer(2)]]){constexpr sampler z(filter::linear);float4 q=t.sample(z,i.u);return float4(1-((1-q.rgb*n)*(1-s)),q.a)*a;}";
    NSError *metalError=nil;id<MTLLibrary> metalLibrary=[device newLibraryWithSource:source options:nil error:&metalError];MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[metalLibrary newFunctionWithName:@"v"];pd.fragmentFunction=[metalLibrary newFunctionWithName:@"f"];pd.colorAttachments[0].pixelFormat=view.colorPixelFormat;pd.colorAttachments[0].blendingEnabled=YES;pd.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne;pd.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;pd.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;pd.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;view->_pipeline=[device newRenderPipelineStateWithDescriptor:pd error:&metalError];if(!view->_pipeline){if(error)*error=metalError;return nil;}
    view->_api=new API();
    if (!view->_api->load(libraryURL)) {
        if(error)*error=[NSError errorWithDomain:@"UtataneNicxlive" code:1 userInfo:@{NSLocalizedDescriptionKey:@"libnicxlive.dylibを読み込めなかった"}];
        return nil;
    }
    view->_api->runtimeInit(); RendererConfig config{(int)frame.size.width,(int)frame.size.height};
    view->_textureContext=new TextureContext{device}; ResourceCallbacks callbacks{view->_textureContext,createTexture,updateTexture,releaseTexture};
    if(view->_api->createRenderer(&config,&callbacks,&view->_renderer)!=Result::ok || view->_api->loadPuppet(view->_renderer,puppetURL.fileSystemRepresentation,&view->_puppet)!=Result::ok) {
        if(error)*error=[NSError errorWithDomain:@"UtataneNicxlive" code:2 userInfo:@{NSLocalizedDescriptionKey:@"puppet.inpを読み込めなかった"}]; return nil;
    }
    size_t count=0; view->_api->getParameters(view->_puppet,nullptr,0,&count); std::vector<ParameterInfo> parameters(count);
    view->_api->getParameters(view->_puppet,parameters.data(),parameters.size(),&count);
    for(const auto&p:parameters){std::string name(p.name,p.nameLength);view->_parameters[name]={p.uuid,p.isVec2,p.min,p.max};if(name=="Body::Roll")view->_roll=p.uuid;if(name=="Body::Breath")view->_breath=p.uuid;if(name=="Eye::Blink")view->_blink=p.uuid;}
    view->_started=CFAbsoluteTimeGetCurrent();
    [NSNotificationCenter.defaultCenter addObserver:view
                                           selector:@selector(applicationWillTerminate:)
                                               name:NSApplicationWillTerminateNotification
                                             object:nil];
    return view;
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateMetalLayerScale];
    if (_diagnosticsEnabled) NSLog(@"Utatane nijigenerate Metal view moved to window: %@ frame=%@ drawable=%@ contentsScale=%.3f", self.window, NSStringFromRect(self.frame), NSStringFromSize(self.drawableSize), self.layer.contentsScale);
}
- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self updateMetalLayerScale];
}
- (void)updateMetalLayerScale {
    CGFloat scale=self.window.backingScaleFactor;
    if(scale<=0)scale=NSScreen.mainScreen.backingScaleFactor;
    if(scale<=0)scale=1;
    self.layer.contentsScale=scale;
    self.drawableSize=CGSizeMake(self.bounds.size.width*scale,self.bounds.size.height*scale);
}
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    // The Metal surface itself stays transparent to input. An interaction
    // overlay, when installed as a child, still receives the normal shell
    // drag, context-menu and SHIORI event handling.
    return hit == self ? nil : hit;
}
- (BOOL)isOpaque { return NO; }
- (void)setPuppetScaleX:(CGFloat)scaleX y:(CGFloat)scaleY {
    if (_isShuttingDown || !_api || !_puppet) return;
    _api->setPuppetScale(_puppet, (float)scaleX, (float)scaleY);
    self.needsDisplay=YES;
}
- (void)setContentOffsetX:(CGFloat)offsetX y:(CGFloat)offsetY {
    _contentOffsetX=offsetX; _contentOffsetY=offsetY; self.needsDisplay=YES;
}
- (BOOL)setParameterNamed:(NSString *)name x:(CGFloat)valueX y:(CGFloat)valueY {
    if (_isShuttingDown || !_api || !_puppet) return NO;
    auto found=_parameters.find(name.UTF8String);
    if(found==_parameters.end())return NO;
    const auto&parameter=found->second;
    auto clamp=[](float value,float minimum,float maximum){return std::fmax(minimum,std::fmin(value,maximum));};
    _parameterOverrides[parameter.uuid]={
        clamp((float)valueX,parameter.min.x,parameter.max.x),
        parameter.isVec2?clamp((float)valueY,parameter.min.y,parameter.max.y):0
    };
    self.needsDisplay=YES;
    return YES;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self shutdownRenderer];
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}
- (void)drawInMTKView:(MTKView *)view {
    (void)view;
    if (_isShuttingDown || !_api || !_renderer || !_puppet) return;
    id<CAMetalDrawable> drawable=self.currentDrawable;MTLRenderPassDescriptor *pass=self.currentRenderPassDescriptor;if(!drawable||!pass){if(_diagnosticsEnabled)NSLog(@"Utatane nijigenerate Metal frame skipped: drawable=%@ pass=%@ frame=%@ drawableSize=%@",drawable,pass,NSStringFromRect(self.frame),NSStringFromSize(self.drawableSize));return;}
    int layoutWidth=self.bounds.size.width, layoutHeight=self.bounds.size.height;
    double elapsed=CFAbsoluteTimeGetCurrent()-_started; std::vector<ParameterUpdate> updates;
    if(_roll&&_parameterOverrides.find(_roll)==_parameterOverrides.end())updates.push_back({_roll,{(float)std::sin(elapsed*2.2),0}}); if(_breath&&_parameterOverrides.find(_breath)==_parameterOverrides.end())updates.push_back({_breath,{(float)((std::sin(elapsed*0.5*M_PI-0.5*M_PI)+1.0)*0.5),0}}); if(_blink&&_parameterOverrides.find(_blink)==_parameterOverrides.end()){double phase=std::fmod(elapsed,3.0);float value=phase>=2.5?(float)std::sin((phase-2.5)/0.5*M_PI):0;updates.push_back({_blink,{value,0}});} for(const auto&entry:_parameterOverrides)updates.push_back({entry.first,entry.second});
    if(!updates.empty())_api->updateParameters(_puppet,updates.data(),updates.size()); FrameConfig frame{layoutWidth,layoutHeight}; _api->beginFrame(_renderer,&frame); _api->tickPuppet(_puppet,1.0/30.0);
    SharedBuffers buffers{}; _api->getSharedBuffers(_renderer,&buffers);
    QueueView queue{}; _api->emitCommands(_renderer,&queue);if(_diagnosticsEnabled&&!_didLogFirstFrame){_didLogFirstFrame=true;NSLog(@"Utatane nijigenerate Metal submitting frame: commands=%zu layout=%dx%d drawable=%zux%zu",queue.count,layoutWidth,layoutHeight,drawable.texture.width,drawable.texture.height);}id<MTLCommandBuffer> command=[_commandQueue commandBuffer];id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];[encoder setRenderPipelineState:_pipeline];Vec2 contentOffset{(float)(2.0*_contentOffsetX/layoutWidth),(float)(-2.0*_contentOffsetY/layoutHeight)};
    for(size_t i=0;i<queue.count;i++){const auto&packet=queue.commands[i].part;if(queue.commands[i].kind!=CommandKind::drawPart||!packet.renderable||!packet.textureCount||!packet.indexCount)continue;
        std::vector<Vertex> vertices(packet.vertexCount);for(size_t j=0;j<packet.vertexCount;j++)vertices[j]={{buffers.vertices.data[packet.vertexOffset+j]+buffers.deform.data[packet.deformOffset+j],buffers.vertices.data[packet.vertexStride+packet.vertexOffset+j]+buffers.deform.data[packet.deformStride+packet.deformOffset+j]},{buffers.uvs.data[packet.uvOffset+j],buffers.uvs.data[packet.uvStride+packet.uvOffset+j]}};
        id<MTLBuffer> vb=[self.device newBufferWithBytes:vertices.data() length:vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];id<MTLBuffer> ib=[self.device newBufferWithBytes:packet.indices length:packet.indexCount*sizeof(uint16_t) options:MTLResourceStorageModeShared];float mvp[16];multiply(packet.renderMatrix,packet.modelMatrix,mvp);[encoder setVertexBuffer:vb offset:0 atIndex:0];[encoder setVertexBytes:mvp length:sizeof(mvp) atIndex:1];[encoder setVertexBytes:&packet.origin length:sizeof(packet.origin) atIndex:2];[encoder setVertexBytes:&contentOffset length:sizeof(contentOffset) atIndex:3];[encoder setFragmentTexture:(__bridge id<MTLTexture>)reinterpret_cast<void *>(packet.textures[0]) atIndex:0];[encoder setFragmentBytes:&packet.opacity length:sizeof(packet.opacity) atIndex:0];[encoder setFragmentBytes:&packet.tint length:sizeof(packet.tint) atIndex:1];[encoder setFragmentBytes:&packet.screen length:sizeof(packet.screen) atIndex:2];[encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:packet.indexCount indexType:MTLIndexTypeUInt16 indexBuffer:ib indexBufferOffset:0];
    }[encoder endEncoding];_api->flush(_renderer);id<MTLBuffer> readback=nil;NSUInteger readbackRowBytes=0;if(!self.framebufferOnly&&!_didInspectFrame){_didInspectFrame=true;readbackRowBytes=(drawable.texture.width*4+255)&~255;readback=[self.device newBufferWithLength:readbackRowBytes*drawable.texture.height options:MTLResourceStorageModeShared];id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];[blit copyFromTexture:drawable.texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(drawable.texture.width,drawable.texture.height,1) toBuffer:readback destinationOffset:0 destinationBytesPerRow:readbackRowBytes destinationBytesPerImage:readbackRowBytes*drawable.texture.height];[blit endEncoding];}[command presentDrawable:drawable];[command commit];
    if(readback){[command waitUntilCompleted];const uint8_t *pixels=(const uint8_t *)readback.contents;NSUInteger visiblePixels=0;for(NSUInteger y=0;y<drawable.texture.height;y++)for(NSUInteger x=0;x<drawable.texture.width;x++)if(pixels[y*readbackRowBytes+x*4+3])visiblePixels++;_lastFrameHadVisiblePixels=visiblePixels>0;if(_diagnosticsEnabled)NSLog(@"Utatane nijigenerate Metal frame pixels: visible=%lu total=%lu",(unsigned long)visiblePixels,(unsigned long)(drawable.texture.width*drawable.texture.height));}
}
- (void)shutdownRenderer {
    if (_isShuttingDown) return;
    _isShuttingDown=true;
    self.paused=YES;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if(_puppet&&_api){_api->unloadPuppet(_renderer,_puppet);_puppet=nullptr;}
    if(_renderer&&_api){_api->destroyRenderer(_renderer);_renderer=nullptr;}
    if(_api){_api->runtimeTerm();delete _api;_api=nullptr;}delete _textureContext;_textureContext=nullptr;
}
- (void)dealloc { [self shutdownRenderer]; }
- (BOOL)lastFrameHadVisiblePixels { return _lastFrameHadVisiblePixels; }
@end


NSView *UTCreateNicxliveView(NSRect frame, NSURL *puppetURL, NSURL *libraryURL, NSError **error) {
    return [UTNicxliveView viewWithFrame:frame puppetURL:puppetURL libraryURL:libraryURL error:error];
}

void UTSetNicxliveViewScale(NSView *view, CGFloat scaleX, CGFloat scaleY) {
    if (![view isKindOfClass:UTNicxliveView.class]) return;
    [(UTNicxliveView *)view setPuppetScaleX:scaleX y:scaleY];
}

void UTSetNicxliveViewOffset(NSView *view, CGFloat offsetX, CGFloat offsetY) {
    if (![view isKindOfClass:UTNicxliveView.class]) return;
    [(UTNicxliveView *)view setContentOffsetX:offsetX y:offsetY];
}

BOOL UTSetNicxliveViewParameter(NSView *view, NSString *name, CGFloat valueX, CGFloat valueY) {
    if (![view isKindOfClass:UTNicxliveView.class]) return NO;
    return [(UTNicxliveView *)view setParameterNamed:name x:valueX y:valueY];
}

BOOL UTNicxliveViewLastFrameHadVisiblePixels(NSView *view) {
    if (![view isKindOfClass:UTNicxliveView.class]) return NO;
    UTNicxliveView *metalView=(UTNicxliveView *)view;
    if (!metalView.framebufferOnly) [metalView drawInMTKView:metalView];
    return [metalView lastFrameHadVisiblePixels];
}
