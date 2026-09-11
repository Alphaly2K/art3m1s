#import "Runtime.h"
#import <dlfcn.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *logPath;
static NSString *pendingPath;
static int logFD = -1;
static BOOL recovering;
static BOOL recording = YES;

static NSString *Localized(NSString *english, NSString *chinese) {
  return [NSLocale.preferredLanguages.firstObject hasPrefix:@"zh"] ? chinese : english;
}

static void Record(NSString *message) {
  if (!recording) return;
  @synchronized (logPath) {
    // Only startup milestones are recorded; cap each session even on repeated failures.
    if (logFD < 0 || lseek(logFD, 0, SEEK_END) > 64 * 1024) return;
    NSData *data = [[NSString stringWithFormat:@"%@ %@\n", NSDate.date, message]
        dataUsingEncoding:NSUTF8StringEncoding];
    const char *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining) {
      ssize_t count = write(logFD, bytes, remaining);
      if (count <= 0) break;
      bytes += count;
      remaining -= count;
    }
    fsync(logFD);
  }
}

@class ARTBootController;

@interface ARTAppDelegate : UIResponder <UIApplicationDelegate, UINavigationControllerDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) id<ARTApplicationRuntime> runtime;
@property(nonatomic, copy) NSDictionary *launchOptions;
@property(nonatomic, strong) ARTBootController *boot;
@property(nonatomic, strong) UINavigationController *navigation;
@property(nonatomic, strong) NSArray<NSDictionary *> *steps;
@property(nonatomic) NSUInteger stepIndex;
@property(nonatomic, strong) NSMutableArray<void (^)(void)> *pendingEvents;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL firstFrame;
@property(nonatomic) BOOL presentationFinished;
@property(nonatomic) BOOL handoffFinished;
@property(nonatomic) BOOL failed;
@property(nonatomic) NSTimeInterval startupTime;
@property(nonatomic) NSTimeInterval activeWait;
@property(nonatomic, strong) NSTimer *watchdog;
- (void)startRuntime;
- (void)nextLibrary;
- (void)attachFlutter;
- (void)finishHandoff;
- (void)fail:(NSString *)message;
- (void)sendOrQueue:(dispatch_block_t)event;
@end

// Retain the native owner after handing UIApplication.delegate to Flutter, as Trace does.
static ARTAppDelegate *startupOwner;

@interface ARTBootController : UIViewController
@property(nonatomic, weak) ARTAppDelegate *owner;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) UIButton *retry;
@property(nonatomic, strong) UIButton *share;
- (void)showFailure:(NSString *)message;
@end

@implementation ARTBootController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.systemBackgroundColor;
  UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:
      [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
       @"Frameworks/App.framework/flutter_assets/assets/branding/art3m1s-logo-v1.png"]]];
  logo.contentMode = UIViewContentModeScaleAspectFit;
  [logo.widthAnchor constraintEqualToConstant:80].active = YES;
  [logo.heightAnchor constraintEqualToConstant:80].active = YES;
  UILabel *title = [UILabel new];
  title.text = @"Art3m1s";
  title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
  self.status = [UILabel new];
  self.status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
  self.status.textColor = UIColor.secondaryLabelColor;
  self.status.textAlignment = NSTextAlignmentCenter;
  self.status.numberOfLines = 0;
  self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
  self.retry = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.retry setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
  [self.retry setTitle:Localized(@"  Retry", @"  \u91cd\u8bd5") forState:UIControlStateNormal];
  self.retry.accessibilityIdentifier = @"startup.retry";
  [self.retry addTarget:self action:@selector(retryStartup) forControlEvents:UIControlEventTouchUpInside];
  self.share = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.share setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
  [self.share setTitle:Localized(@"  Share Log", @"  \u5206\u4eab\u65e5\u5fd7") forState:UIControlStateNormal];
  self.share.accessibilityIdentifier = @"startup.share";
  [self.share addTarget:self action:@selector(shareLog) forControlEvents:UIControlEventTouchUpInside];
  for (UIButton *button in @[self.retry, self.share]) {
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
  }
  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
      @[logo, title, self.status, self.spinner, self.retry, self.share]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.spacing = 16;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stack];
  NSLayoutConstraint *preferredWidth = [stack.widthAnchor constraintEqualToConstant:320];
  preferredWidth.priority = UILayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[
    preferredWidth,
    [stack.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
    [stack.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
    [stack.widthAnchor constraintLessThanOrEqualToConstant:360],
    [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
  ]];
  if (recovering) {
    [self showFailure:Localized(@"Previous startup did not finish.", @"\u4e0a\u6b21\u542f\u52a8\u672a\u5b8c\u6210\u3002")];
  } else {
    self.status.text = Localized(@"Starting...", @"\u6b63\u5728\u542f\u52a8...");
    self.retry.hidden = self.share.hidden = YES;
    [self.spinner startAnimating];
  }
}
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (!recovering && !self.owner.started) {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.owner startRuntime]; });
  }
}
- (void)showFailure:(NSString *)message {
  [self loadViewIfNeeded];
  self.status.text = message;
  [self.spinner stopAnimating];
  self.retry.hidden = self.owner.started;
  self.share.hidden = NO;
}
- (void)retryStartup {
  self.retry.hidden = self.share.hidden = YES;
  self.status.text = Localized(@"Starting...", @"\u6b63\u5728\u542f\u52a8...");
  [self.spinner startAnimating];
  [self.owner startRuntime];
}
- (void)shareLog {
  NSMutableArray *files = [NSMutableArray array];
  for (NSString *path in @[logPath, [logPath stringByAppendingString:@".previous"]]) {
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) [files addObject:[NSURL fileURLWithPath:path]];
  }
  if (!files.count) return;
  UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
  sheet.popoverPresentationController.sourceView = self.share;
  sheet.popoverPresentationController.sourceRect = self.share.bounds;
  [self presentViewController:sheet animated:YES completion:nil];
}
@end

@implementation ARTAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
  startupOwner = self;
  self.launchOptions = options ?: @{};
  self.pendingEvents = [NSMutableArray array];
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.boot = [ARTBootController new];
  self.boot.owner = self;
  self.navigation = [[UINavigationController alloc] initWithRootViewController:self.boot];
  self.navigation.delegate = self;
  self.navigation.navigationBarHidden = YES;
  self.window.rootViewController = self.navigation;
  [self.window makeKeyAndVisible];
  Record(@"NATIVE_WINDOW_READY legacy-uiwindow");
  return YES;
}
- (void)sendOrQueue:(dispatch_block_t)event {
  if (self.handoffFinished) event();
  else if (self.pendingEvents.count < 64) [self.pendingEvents addObject:[event copy]];
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary *)options {
  [self sendOrQueue:^{
    id<UIApplicationDelegate> target = self.runtime.applicationDelegate;
    if ([target respondsToSelector:_cmd]) [target application:application openURL:url options:options];
  }];
  return YES;
}
- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)activity
    restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *))handler {
  [self sendOrQueue:^{
    id<UIApplicationDelegate> target = self.runtime.applicationDelegate;
    if ([target respondsToSelector:_cmd]) [target application:application continueUserActivity:activity restorationHandler:handler];
  }];
  return YES;
}
- (void)startRuntime {
  if (self.started) return;
  self.started = YES;
  recovering = NO;
  self.startupTime = NSProcessInfo.processInfo.systemUptime;
  NSError *error = nil;
  if (![@"pending\n" writeToFile:pendingPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
    Record([@"MARKER_ERROR " stringByAppendingString:error.description]);
  } else {
    int marker = open(pendingPath.fileSystemRepresentation, O_RDONLY);
    if (marker >= 0) { fsync(marker); close(marker); }
  }
  NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:
      [NSBundle.mainBundle pathForResource:@"NativeLibraries" ofType:@"plist"]];
  self.steps = manifest[@"steps"];
  if (!self.steps.count) { [self fail:@"Startup library manifest is missing."]; return; }
  Record(@"BEGIN RUNTIME_LOAD RTLD_LAZY|RTLD_GLOBAL async-main-queue");
  [self nextLibrary];
}
- (void)nextLibrary {
  if (self.failed) return;
  if (self.stepIndex == self.steps.count) { [self attachFlutter]; return; }
  NSDictionary *step = self.steps[self.stepIndex++];
  NSString *name = step[@"path"];
  NSString *path = [name hasPrefix:@"/"] ? name : [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:name];
#if ART_STARTUP_DIAGNOSTICS
  Record([@"LOAD " stringByAppendingString:name]);
#endif
  // Use Trace's serial main-queue loading without its per-step diagnostic delay.
  dispatch_async(dispatch_get_main_queue(), ^{
    @try {
      dlerror();
      void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_GLOBAL);
      if (!handle) {
        const char *detail = dlerror();
        NSString *message = detail ? @(detail) : @"Unknown library loading error";
        if (![step[@"weak"] boolValue]) { [self fail:message]; return; }
        Record([@"OPTIONAL_MISSING " stringByAppendingString:message]);
      }
      // Keep handles open for process-wide FFI and flat-namespace lookups.
      [self nextLibrary];
    } @catch (NSException *exception) {
      [self fail:[NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]];
    }
  });
}
- (void)attachFlutter {
  @try {
    ARTCreateRuntime create = (ARTCreateRuntime)dlsym(RTLD_DEFAULT, "Art3m1sCreateRuntime");
    if (!create) { [self fail:@"Flutter runtime entry point is missing."]; return; }
    self.runtime = create();
    __weak ARTAppDelegate *weakSelf = self;
    UIViewController *controller = [self.runtime prepareInWindow:self.window launchOptions:self.launchOptions
        firstFrame:^{
          dispatch_async(dispatch_get_main_queue(), ^{
            ARTAppDelegate *owner = weakSelf;
            if (!owner || owner.firstFrame || owner.failed) return;
            owner.firstFrame = YES;
            [owner.watchdog invalidate];
            owner.watchdog = nil;
            Record([NSString stringWithFormat:@"FLUTTER_FIRST_FRAME startup=%.3fs",
                NSProcessInfo.processInfo.systemUptime - owner.startupTime]);
            [owner finishHandoff];
          });
        } log:^(NSString *message) { Record(message); }
        error:^(NSString *message) {
          dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf fail:message]; });
        }];
    if (!controller) { [self fail:@"Flutter runtime could not start."]; return; }
    self.ready = YES;
    [self.navigation pushViewController:controller animated:YES];
    Record(@"FLUTTER_VIEW_ATTACHED");
    self.activeWait = 0;
    // Suspended time is excluded. This timer is removed at the first frame.
    self.watchdog = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
      ARTAppDelegate *owner = weakSelf;
      if (!owner || owner.firstFrame || owner.failed) { [timer invalidate]; return; }
      if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) owner.activeWait++;
      if (owner.activeWait >= 30) [owner fail:@"First frame timed out after 30 active seconds."];
    }];
  } @catch (NSException *exception) {
    [self fail:[NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]];
  }
}
- (void)navigationController:(UINavigationController *)navigationController
       didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
  if (self.ready && viewController != self.boot) {
    self.presentationFinished = YES;
    [self finishHandoff];
  }
}
- (void)finishHandoff {
  if (!self.firstFrame || !self.presentationFinished || self.handoffFinished || self.failed) return;
  self.handoffFinished = YES;
  // Do not reparent a Flutter view while its navigation appearance is in flight.
  dispatch_async(dispatch_get_main_queue(), ^{
    UIViewController *flutter = self.navigation.topViewController;
    self.navigation.delegate = nil;
    [self.navigation setViewControllers:@[self.boot] animated:NO];
    // Finish the old container's disappearance before UIKit presents the new root.
    dispatch_async(dispatch_get_main_queue(), ^{
      self.window.rootViewController = flutter;
      self.navigation = nil;
      self.boot = nil;
      [NSFileManager.defaultManager removeItemAtPath:pendingPath error:nil];
      Record(@"FLUTTER_ROOT_READY");
      recording = NO;
      NSArray *events = [self.pendingEvents copy];
      [self.pendingEvents removeAllObjects];
      for (dispatch_block_t event in events) event();
    });
  });
}
- (void)fail:(NSString *)message {
  Record([@"STARTUP_FAILED " stringByAppendingString:message]);
  if (self.firstFrame) return;
  self.failed = YES;
  [self.watchdog invalidate];
  self.watchdog = nil;
  [self.navigation setViewControllers:@[self.boot] animated:NO];
  [self.boot showFailure:Localized(@"Startup did not finish. Share the log, then close and reopen the app to retry.",
      @"\u542f\u52a8\u672a\u5b8c\u6210\u3002\u53ef\u5148\u5206\u4eab\u65e5\u5fd7\uff0c\u518d\u5173\u95ed\u5e76\u91cd\u65b0\u6253\u5f00\u5e94\u7528\u91cd\u8bd5\u3002")];
}
@end

int main(int argc, char **argv) {
  @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    [fm createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
    logPath = [documents stringByAppendingPathComponent:@"startup-native.log"];
    pendingPath = [support stringByAppendingPathComponent:@"art3m1s-startup.pending"];
    recovering = [fm fileExistsAtPath:pendingPath];
    NSString *previous = [logPath stringByAppendingString:@".previous"];
    // Preserve one failed session separately, without combining process logs.
    if (recovering && [fm fileExistsAtPath:logPath]) {
      NSString *lastLog = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
      if ([lastLog containsString:@"BEGIN RUNTIME_LOAD"]) {
        [fm removeItemAtPath:previous error:nil];
        [fm moveItemAtPath:logPath toPath:previous error:nil];
      }
    } else if (!recovering) {
      [fm removeItemAtPath:previous error:nil];
    }
    logFD = open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    Record([NSString stringWithFormat:@"SESSION %@ pid=%d recovery=%d", NSProcessInfo.processInfo.operatingSystemVersionString, getpid(), recovering]);
    return UIApplicationMain(argc, argv, nil, NSStringFromClass(ARTAppDelegate.class));
  }
}
