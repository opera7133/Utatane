#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Experimental nicxlive-backed view. The runtime is loaded dynamically so
/// Utatane can still build and run when nicxlive is not installed.
@interface UTNicxliveView : MTKView <MTKViewDelegate>

+ (nullable instancetype)viewWithFrame:(NSRect)frame
                             puppetURL:(NSURL *)puppetURL
                            libraryURL:(NSURL *)libraryURL
                                 error:(NSError **)error;

@end

FOUNDATION_EXPORT NSView * _Nullable UTCreateNicxliveView(
    NSRect frame,
    NSURL *puppetURL,
    NSURL *libraryURL,
    NSError **error
);

FOUNDATION_EXPORT void UTSetNicxliveViewScale(NSView *view, CGFloat scaleX, CGFloat scaleY);
FOUNDATION_EXPORT void UTSetNicxliveViewOffset(NSView *view, CGFloat offsetX, CGFloat offsetY);

FOUNDATION_EXPORT BOOL UTSetNicxliveViewParameter(
    NSView *view,
    NSString *name,
    CGFloat valueX,
    CGFloat valueY
);

/// Returns whether the most recently verified Metal frame contained a visible pixel.
FOUNDATION_EXPORT BOOL UTNicxliveViewLastFrameHadVisiblePixels(NSView *view);

NS_ASSUME_NONNULL_END
