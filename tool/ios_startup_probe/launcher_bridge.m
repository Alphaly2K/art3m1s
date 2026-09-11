#import <Flutter/Flutter.h>

extern void Art3m1sTraceMessage(NSString *message);
static id<UIApplicationDelegate> runnerDelegate;
static id<UIApplicationDelegate> nativeDelegate;

UIViewController *Art3m1sStartApplication(UIWindow *window) {
  Class delegateClass = NSClassFromString(@"Runner.AppDelegate") ?: NSClassFromString(@"AppDelegate");
  if (!delegateClass) {
    Art3m1sTraceMessage(@"FAILED: Runner AppDelegate class not found");
    return nil;
  }
  Art3m1sTraceMessage(@"BEGIN RUNNER_DELEGATE_INIT");
  runnerDelegate = [delegateClass new];
  nativeDelegate = UIApplication.sharedApplication.delegate;
  runnerDelegate.window = window;
  UIApplication.sharedApplication.delegate = runnerDelegate;
  Art3m1sTraceMessage(@"END RUNNER_DELEGATE_INIT");
  if ([runnerDelegate respondsToSelector:@selector(application:willFinishLaunchingWithOptions:)]) {
    if (![runnerDelegate application:UIApplication.sharedApplication willFinishLaunchingWithOptions:nil]) {
      Art3m1sTraceMessage(@"FAILED: willFinishLaunching returned NO");
      return nil;
    }
  }
  if ([runnerDelegate respondsToSelector:@selector(application:didFinishLaunchingWithOptions:)]) {
    if (![runnerDelegate application:UIApplication.sharedApplication didFinishLaunchingWithOptions:nil]) {
      Art3m1sTraceMessage(@"FAILED: didFinishLaunching returned NO");
      return nil;
    }
  }
  Art3m1sTraceMessage(@"BEGIN RUNNER_STORYBOARD");
  UIViewController *controller = [[UIStoryboard storyboardWithName:@"Main" bundle:NSBundle.mainBundle]
      instantiateInitialViewController];
  Art3m1sTraceMessage(@"END RUNNER_STORYBOARD");
  if (![controller isKindOfClass:NSClassFromString(@"FlutterViewController")]) {
    Art3m1sTraceMessage(@"FAILED: Main storyboard did not return a FlutterViewController");
    return nil;
  }
  [(FlutterViewController *)controller setFlutterViewDidRenderCallback:^{
    Art3m1sTraceMessage(@"FLUTTER_FIRST_FRAME");
  }];
  return controller;
}
