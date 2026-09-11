#import <Flutter/Flutter.h>
#import "../Native/Runtime.h"

@interface ARTRuntime : NSObject <ARTApplicationRuntime>
@property(nonatomic, strong) FlutterAppDelegate *delegate;
@property(nonatomic, strong) FlutterViewController *controller;
@property(nonatomic, strong) FlutterMethodChannel *startupChannel;
@end

@implementation ARTRuntime
- (instancetype)init {
  if ((self = [super init])) {
    self.delegate = [NSClassFromString(@"Art3m1sRuntimeDelegate") new];
  }
  return self;
}
- (NSObject<UIApplicationDelegate> *)applicationDelegate { return self.delegate; }

- (UIViewController *)prepareInWindow:(UIWindow *)window
                       launchOptions:(NSDictionary *)options
                          firstFrame:(dispatch_block_t)firstFrame
                                 log:(ARTStartupLog)log
                               error:(void (^)(NSString *))error {
  if (!self.delegate || self.controller) return nil;
  self.delegate.window = window;
  UIApplication *application = UIApplication.sharedApplication;
  application.delegate = self.delegate;
  log(@"BEGIN RUNNER_LAUNCH_EVENTS");
  if (![self.delegate application:application willFinishLaunchingWithOptions:options] ||
      ![self.delegate application:application didFinishLaunchingWithOptions:options]) {
    error(@"The application rejected startup.");
    return nil;
  }
  log(@"BEGIN RUNNER_STORYBOARD");
  // Same storyboard/implicit-engine path and delegate handoff as the successful Trace.
  UIViewController *controller = [[UIStoryboard storyboardWithName:@"Main" bundle:NSBundle.mainBundle]
      instantiateInitialViewController];
  if (![controller isKindOfClass:FlutterViewController.class]) return nil;
  self.controller = (FlutterViewController *)controller;
  log(@"END FLUTTER_CONTROLLER_AND_PLUGINS");
  self.startupChannel = [FlutterMethodChannel methodChannelWithName:@"moe.alphaly.art3m1s/startup"
                                                  binaryMessenger:self.controller.binaryMessenger];
  [self.startupChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult reply) {
    if ([call.method isEqualToString:@"stage"] && [call.arguments isKindOfClass:NSString.class]) {
#if ART_STARTUP_DIAGNOSTICS
      log([@"DART " stringByAppendingString:call.arguments]);
#endif
      reply(nil);
    } else if ([call.method isEqualToString:@"failed"] && [call.arguments isKindOfClass:NSString.class]) {
      log([@"DART_ERROR " stringByAppendingString:call.arguments]);
      error(call.arguments);
      reply(nil);
    } else {
      reply(FlutterMethodNotImplemented);
    }
  }];
  [self.controller setFlutterViewDidRenderCallback:firstFrame];
  log(@"BEGIN PLUGIN_LAUNCH_EVENTS");
  // Trace's early launch calls ran before plugin registration. Deliver each
  // plugin's launch events now that the storyboard has registered the plugins.
  if (![self.delegate application:application willFinishLaunchingWithOptions:options] ||
      ![self.delegate application:application didFinishLaunchingWithOptions:options]) {
    error(@"A plugin rejected application startup.");
    return nil;
  }
  log(@"END PLUGIN_LAUNCH_EVENTS");
  return self.controller;
}
@end

__attribute__((visibility("default"))) id<ARTApplicationRuntime> Art3m1sCreateRuntime(void) {
  return [ARTRuntime new];
}
