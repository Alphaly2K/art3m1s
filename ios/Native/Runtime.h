#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ARTStartupLog)(NSString *message);

// Shared ABI: the native executable must not import or link Flutter.
@protocol ARTApplicationRuntime <NSObject>
@property(nonatomic, readonly) NSObject<UIApplicationDelegate> *applicationDelegate;
- (nullable UIViewController *)prepareInWindow:(UIWindow *)window
                                launchOptions:(NSDictionary *)options
                                   firstFrame:(dispatch_block_t)firstFrame
                                          log:(ARTStartupLog)log
                                        error:(void (^)(NSString *message))error;
@end

typedef id<ARTApplicationRuntime> _Nonnull (*ARTCreateRuntime)(void);

NS_ASSUME_NONNULL_END
