#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OctronTelegramHost : NSObject
+ (NSWindow *)makeWindowWithContentRect:(NSRect)contentRect;
- (instancetype)initWithWindow:(NSWindow *)window NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) NSView *sidebarView;
@property(nonatomic, readonly) NSView *chatView;
- (BOOL)startAndReturnError:(NSError * _Nullable *)error;
- (void)setActive:(BOOL)active;
- (void)applyThemeWithBackground:(NSColor *)background
              sidebarBackground:(NSColor *)sidebarBackground
                    textPrimary:(NSColor *)textPrimary
                   textInactive:(NSColor *)textInactive
                   textDisabled:(NSColor *)textDisabled
                         accent:(NSColor *)accent;
- (void)prepareForTermination;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
