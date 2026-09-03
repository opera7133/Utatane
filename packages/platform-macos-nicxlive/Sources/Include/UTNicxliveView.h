#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Experimental nicxlive-backed view. The runtime is loaded dynamically so
/// Utatane can still build and run when nicxlive is not installed.
@interface UTNicxliveView : NSOpenGLView

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

NS_ASSUME_NONNULL_END
