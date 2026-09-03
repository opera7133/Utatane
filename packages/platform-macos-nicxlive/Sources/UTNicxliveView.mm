#import "UTNicxliveView.h"

#import <OpenGL/gl3.h>
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

GLuint compile(GLenum kind, const char *source) {
    GLuint shader = glCreateShader(kind); glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader); return shader;
}
GLuint program() {
    const char *vs = "#version 150 core\nin float vx,vy,ux,uy,dx,dy; uniform mat4 mvp; uniform vec2 origin,contentOffset; out vec2 uv; void main(){gl_Position=mvp*vec4(vx-origin.x+dx,vy-origin.y+dy,0,1);gl_Position.xy+=contentOffset*gl_Position.w;uv=vec2(ux,uy);}";
    const char *fs = "#version 150 core\nuniform sampler2D tex; uniform float opacity; uniform vec3 tint,screen; in vec2 uv; out vec4 color; void main(){vec4 s=texture(tex,uv);vec3 rgb=1.0-((1.0-s.rgb*tint)*(1.0-screen));color=vec4(rgb,s.a)*opacity;}";
    GLuint v = compile(GL_VERTEX_SHADER, vs), f = compile(GL_FRAGMENT_SHADER, fs), p = glCreateProgram();
    glAttachShader(p,v); glAttachShader(p,f);
    const char *names[] = {"vx","vy","ux","uy","dx","dy"};
    for (GLuint i=0;i<6;i++) glBindAttribLocation(p,i,names[i]);
    glLinkProgram(p); glDeleteShader(v); glDeleteShader(f); return p;
}
size_t createTexture(int w,int h,int channels,int,int,bool,bool,void*) {
    GLuint t=0; glGenTextures(1,&t); glBindTexture(GL_TEXTURE_2D,t);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    GLenum format=channels==3?GL_RGB:GL_RGBA; glTexImage2D(GL_TEXTURE_2D,0,format,w,h,0,format,GL_UNSIGNED_BYTE,nullptr); return t;
}
void updateTexture(size_t h,const uint8_t*d,size_t,int w,int height,int c,void*) {
    glBindTexture(GL_TEXTURE_2D,(GLuint)h); glPixelStorei(GL_UNPACK_ALIGNMENT,1);
    GLenum f=c==3?GL_RGB:GL_RGBA; glTexSubImage2D(GL_TEXTURE_2D,0,0,0,w,height,f,GL_UNSIGNED_BYTE,d);
}
void releaseTexture(size_t h,void*) { GLuint t=(GLuint)h; glDeleteTextures(1,&t); }
void multiply(const Mat4&a,const Mat4&b,float out[16]) {
    for(int r=0;r<4;r++) for(int c=0;c<4;c++){ float v=0; for(int k=0;k<4;k++)v+=a.values[r][k]*b.values[k][c]; out[r*4+c]=v; }
}

} // namespace

@implementation UTNicxliveView {
    API *_api; void *_renderer; void *_puppet; uint32_t _roll, _breath, _blink;
    std::unordered_map<std::string, ParameterDescriptor> _parameters;
    std::unordered_map<uint32_t, Vec2> _parameterOverrides;
    GLuint _program, _vao, _vertices, _uvs, _deform; NSTimer *_timer; CFAbsoluteTime _started;
    CGFloat _contentOffsetX, _contentOffsetY;
    bool _isShuttingDown;
}

+ (instancetype)viewWithFrame:(NSRect)frame puppetURL:(NSURL *)puppetURL libraryURL:(NSURL *)libraryURL error:(NSError **)error {
    NSOpenGLPixelFormatAttribute attrs[]={NSOpenGLPFAOpenGLProfile,NSOpenGLProfileVersion3_2Core,NSOpenGLPFAColorSize,24,NSOpenGLPFAAlphaSize,8,NSOpenGLPFADoubleBuffer,NSOpenGLPFAAccelerated,0};
    NSOpenGLPixelFormat *format=[[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    UTNicxliveView *view=[[self alloc] initWithFrame:frame pixelFormat:format];
    view->_api=new API();
    if (!view->_api->load(libraryURL)) {
        if(error)*error=[NSError errorWithDomain:@"UtataneNicxlive" code:1 userInfo:@{NSLocalizedDescriptionKey:@"libnicxlive.dylibを読み込めなかった"}];
        return nil;
    }
    [[view openGLContext] makeCurrentContext]; view->_program=program(); glGenVertexArrays(1,&view->_vao);
    GLint opaque=0; [[view openGLContext] setValues:&opaque forParameter:NSOpenGLContextParameterSurfaceOpacity];
    glGenBuffers(1,&view->_vertices); glGenBuffers(1,&view->_uvs); glGenBuffers(1,&view->_deform);
    view->_api->runtimeInit(); RendererConfig config{(int)frame.size.width,(int)frame.size.height};
    ResourceCallbacks callbacks{nullptr,createTexture,updateTexture,releaseTexture};
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
    if (self.window && !_timer && !_isShuttingDown) {
        _timer=[NSTimer timerWithTimeInterval:1.0/30.0 target:self selector:@selector(nextFrame:) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    } else if (!self.window) {
        [_timer invalidate]; _timer=nil;
    }
}
- (void)nextFrame:(NSTimer *)timer {
    (void)timer;
    if (!_isShuttingDown) self.needsDisplay=YES;
}
- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    // Mouse handling belongs to Utatane's parent SurfaceImageView so the live
    // renderer gets the same drag, context-menu and SHIORI event behavior as
    // ordinary PNG shells.
    return nil;
}
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
- (void)drawRect:(NSRect)dirtyRect {
    if (_isShuttingDown || !_api || !_renderer || !_puppet) return;
    (void)dirtyRect; [[self openGLContext] makeCurrentContext];
    NSRect backingBounds=[self convertRectToBacking:self.bounds];
    int backingWidth=backingBounds.size.width, backingHeight=backingBounds.size.height;
    int layoutWidth=self.bounds.size.width, layoutHeight=self.bounds.size.height;
    glViewport(0,0,backingWidth,backingHeight); glClearColor(0,0,0,0); glClear(GL_COLOR_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);
    double elapsed=CFAbsoluteTimeGetCurrent()-_started; std::vector<ParameterUpdate> updates;
    if(_roll&&_parameterOverrides.find(_roll)==_parameterOverrides.end())updates.push_back({_roll,{(float)std::sin(elapsed*2.2),0}}); if(_breath&&_parameterOverrides.find(_breath)==_parameterOverrides.end())updates.push_back({_breath,{(float)((std::sin(elapsed*0.5*M_PI-0.5*M_PI)+1.0)*0.5),0}}); if(_blink&&_parameterOverrides.find(_blink)==_parameterOverrides.end()){double phase=std::fmod(elapsed,3.0);float value=phase>=2.5?(float)std::sin((phase-2.5)/0.5*M_PI):0;updates.push_back({_blink,{value,0}});} for(const auto&entry:_parameterOverrides)updates.push_back({entry.first,entry.second});
    if(!updates.empty())_api->updateParameters(_puppet,updates.data(),updates.size()); FrameConfig frame{layoutWidth,layoutHeight}; _api->beginFrame(_renderer,&frame); _api->tickPuppet(_puppet,1.0/30.0);
    SharedBuffers buffers{}; _api->getSharedBuffers(_renderer,&buffers);
    GLuint bs[]={_vertices,_uvs,_deform}; BufferSlice slices[]={buffers.vertices,buffers.uvs,buffers.deform}; for(int i=0;i<3;i++){glBindBuffer(GL_ARRAY_BUFFER,bs[i]);glBufferData(GL_ARRAY_BUFFER,slices[i].length*sizeof(float),slices[i].data,GL_DYNAMIC_DRAW);}
    QueueView queue{}; _api->emitCommands(_renderer,&queue); glUseProgram(_program);glBindVertexArray(_vao);glEnable(GL_BLEND);glBlendFunc(GL_ONE,GL_ONE_MINUS_SRC_ALPHA);glUniform1i(glGetUniformLocation(_program,"tex"),0);glUniform2f(glGetUniformLocation(_program,"contentOffset"),(float)(2.0*_contentOffsetX/layoutWidth),(float)(-2.0*_contentOffsetY/layoutHeight));
    for(size_t i=0;i<queue.count;i++){const auto&packet=queue.commands[i].part;if(queue.commands[i].kind!=CommandKind::drawPart||!packet.renderable||!packet.textureCount||!packet.indexCount)continue;
        glBindTexture(GL_TEXTURE_2D,(GLuint)packet.textures[0]);float mvp[16];multiply(packet.renderMatrix,packet.modelMatrix,mvp);glUniformMatrix4fv(glGetUniformLocation(_program,"mvp"),1,GL_TRUE,mvp);glUniform2f(glGetUniformLocation(_program,"origin"),packet.origin.x,packet.origin.y);glUniform1f(glGetUniformLocation(_program,"opacity"),packet.opacity);glUniform3f(glGetUniformLocation(_program,"tint"),packet.tint.x,packet.tint.y,packet.tint.z);glUniform3f(glGetUniformLocation(_program,"screen"),packet.screen.x,packet.screen.y,packet.screen.z);
        auto lane=[](GLuint buffer,GLuint location,size_t offset){glBindBuffer(GL_ARRAY_BUFFER,buffer);glEnableVertexAttribArray(location);glVertexAttribPointer(location,1,GL_FLOAT,GL_FALSE,0,(void*)(offset*sizeof(float)));}; lane(_vertices,0,packet.vertexOffset);lane(_vertices,1,packet.vertexStride+packet.vertexOffset);lane(_uvs,2,packet.uvOffset);lane(_uvs,3,packet.uvStride+packet.uvOffset);lane(_deform,4,packet.deformOffset);lane(_deform,5,packet.deformStride+packet.deformOffset);
        GLuint index=0;glGenBuffers(1,&index);glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,index);glBufferData(GL_ELEMENT_ARRAY_BUFFER,packet.indexCount*sizeof(uint16_t),packet.indices,GL_STREAM_DRAW);glDrawElements(GL_TRIANGLES,(GLsizei)packet.indexCount,GL_UNSIGNED_SHORT,nullptr);glDeleteBuffers(1,&index);
    } _api->flush(_renderer); [[self openGLContext] flushBuffer];
}
- (void)shutdownRenderer {
    if (_isShuttingDown) return;
    _isShuttingDown=true;
    [_timer invalidate]; _timer=nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [[self openGLContext] makeCurrentContext];
    if(_puppet&&_api){_api->unloadPuppet(_renderer,_puppet);_puppet=nullptr;}
    if(_renderer&&_api){_api->destroyRenderer(_renderer);_renderer=nullptr;}
    if(_api){_api->runtimeTerm();delete _api;_api=nullptr;}
}
- (void)dealloc { [self shutdownRenderer]; }
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
