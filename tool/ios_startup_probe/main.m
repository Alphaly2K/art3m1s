#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <unistd.h>

static NSString *logPath;
static int logFD = -1;
static uint32_t recordedImages;

static void Record(NSString *message) {
  NSData *data = [[NSString stringWithFormat:@"%@ %@\n", NSDate.date, message]
      dataUsingEncoding:NSUTF8StringEncoding];
  const char *bytes = data.bytes;
  NSUInteger remaining = data.length;
  while (remaining > 0) {
    ssize_t count = write(logFD, bytes, remaining);
    if (count <= 0) break;
    bytes += count;
    remaining -= count;
  }
  // The last BEGIN must survive even if dlopen never returns.
  fsync(logFD);
}

static void RecordImages(void) {
  uint32_t count = _dyld_image_count();
  for (uint32_t i = recordedImages; i < count; ++i) {
    const struct mach_header *header = _dyld_get_image_header(i);
    NSString *uuid = @"unknown";
    if (header->magic == MH_MAGIC_64) {
      const struct load_command *command = (const void *)
          ((const struct mach_header_64 *)header + 1);
      for (uint32_t j = 0; j < header->ncmds; ++j) {
        if (command->cmd == LC_UUID) {
          const struct uuid_command *uuidCommand = (const void *)command;
          uuid = [[NSUUID alloc] initWithUUIDBytes:uuidCommand->uuid].UUIDString;
          break;
        }
        command = (const void *)((const char *)command + command->cmdsize);
      }
    }
    Record([NSString stringWithFormat:@"IMAGE %p %@ %s", header, uuid,
                                      _dyld_get_image_name(i)]);
  }
  recordedImages = count;
}

@interface ProbeController : UIViewController
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, strong) UISegmentedControl *bindingMode;
@property(nonatomic, strong) NSArray<NSDictionary *> *steps;
@property(nonatomic, strong) UIBarButtonItem *runButton;
@property(nonatomic, strong) UIBarButtonItem *shareButton;
@property(nonatomic) NSUInteger stepIndex;
@property(nonatomic) BOOL running;
@end

@implementation ProbeController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.title = @"Art3m1s Probe";
  self.view.backgroundColor = UIColor.systemBackgroundColor;
  self.runButton = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                          target:self action:@selector(runProbe)];
  self.runButton.accessibilityLabel = @"Run probe";
  self.shareButton = [[UIBarButtonItem alloc]
      initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                          target:self action:@selector(shareLog)];
  self.shareButton.accessibilityLabel = @"Share log";
  self.navigationItem.rightBarButtonItems = @[self.shareButton, self.runButton];

  self.bindingMode = [[UISegmentedControl alloc] initWithItems:@[@"Lazy", @"Now"]];
  self.bindingMode.selectedSegmentIndex = 0;
  self.bindingMode.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.bindingMode];

  self.output = [[UITextView alloc] initWithFrame:CGRectZero];
  self.output.editable = NO;
  self.output.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
  self.output.textColor = UIColor.labelColor;
  self.output.backgroundColor = UIColor.systemBackgroundColor;
  self.output.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.output];
  UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.bindingMode.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
    [self.bindingMode.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
    [self.bindingMode.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
    [self.output.topAnchor constraintEqualToAnchor:self.bindingMode.bottomAnchor constant:8],
    [self.output.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
    [self.output.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
    [self.output.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
  ]];
  self.output.text = [NSString stringWithContentsOfFile:logPath
      encoding:NSUTF8StringEncoding error:nil] ?: @"";
  [self.output scrollRangeToVisible:NSMakeRange(self.output.text.length, 0)];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
  if ([arguments containsObject:@"--probe-run"] && self.runButton.enabled) {
    self.bindingMode.selectedSegmentIndex = [arguments containsObject:@"--probe-now"] ? 1 : 0;
    [self runProbe];
  }
}

- (void)append:(NSString *)message {
  Record(message);
  self.output.text = [self.output.text stringByAppendingFormat:@"%@\n", message];
  [self.output scrollRangeToVisible:NSMakeRange(self.output.text.length, 0)];
}

- (void)runProbe {
  if (self.running || !self.runButton.enabled) return;
  self.running = YES;
  self.runButton.enabled = NO;
  self.shareButton.enabled = NO;
  self.bindingMode.enabled = NO;
  NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:
      [NSBundle.mainBundle pathForResource:@"ProbeManifest" ofType:@"plist"]];
  self.steps = manifest[@"steps"];
  if (self.steps.count == 0) {
    [self finish:@"ERROR: empty probe manifest"];
    return;
  }
  [self append:[NSString stringWithFormat:@"SOURCE %@", manifest[@"sourceRunnerUUID"]]];
  [self append:self.bindingMode.selectedSegmentIndex == 0 ? @"MODE RTLD_LAZY" : @"MODE RTLD_NOW"];
  RecordImages();
  self.stepIndex = 0;
  [self nextStep];
}

- (void)nextStep {
  if (self.stepIndex == self.steps.count) {
    [self finish:@"COMPLETE: all required libraries loaded; Dart and Runner plugins were not started"];
    return;
  }
  NSDictionary *step = self.steps[self.stepIndex++];
  NSString *path = step[@"path"];
  if (![path hasPrefix:@"/"]) {
    path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:path];
  }
  [self append:[NSString stringWithFormat:@"BEGIN %lu/%lu %@", (unsigned long)self.stepIndex,
      (unsigned long)self.steps.count, step[@"path"]]];
  // Give UIKit a frame to display the pending library before entering dyld.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                 dispatch_get_main_queue(), ^{
    @try {
      dlerror();
      int mode = self.bindingMode.selectedSegmentIndex == 0 ? RTLD_LAZY : RTLD_NOW;
      void *handle = dlopen(path.fileSystemRepresentation, mode | RTLD_GLOBAL);
      if (handle == NULL) {
        const char *error = dlerror();
        NSString *detail = error ? @(error) : @"unknown dlopen error";
        if ([step[@"weak"] boolValue]) {
          [self append:[NSString stringWithFormat:@"OPTIONAL MISSING %@", detail]];
        } else {
          [self finish:[NSString stringWithFormat:@"FAILED %@", detail]];
          return;
        }
      } else {
        [self append:[NSString stringWithFormat:@"OK %@", step[@"path"]]];
      }
      // Keep handles open so later flat-namespace lookups can use their exports.
      RecordImages();
      [self nextStep];
    } @catch (NSException *exception) {
      [self finish:[NSString stringWithFormat:@"EXCEPTION %@ %@\n%@",
          exception.name, exception.reason, exception.callStackSymbols]];
    }
  });
}

- (void)finish:(NSString *)message {
  [self append:message];
  self.running = NO;
  self.shareButton.enabled = YES;
  // A second run would reuse loaded images, invalidating the comparison.
}

- (void)shareLog {
  fsync(logFD);
  UIActivityViewController *sheet = [[UIActivityViewController alloc]
      initWithActivityItems:@[[NSURL fileURLWithPath:logPath]] applicationActivities:nil];
  sheet.popoverPresentationController.barButtonItem = self.shareButton;
  [self presentViewController:sheet animated:YES completion:nil];
}
@end

@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options {
  Record(@"NATIVE_UI_READY");
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [[UINavigationController alloc]
      initWithRootViewController:[ProbeController new]];
  [self.window makeKeyAndVisible];
  return YES;
}
@end

int main(int argc, char **argv) {
  @autoreleasepool {
    NSString *documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [NSFileManager.defaultManager createDirectoryAtPath:documents
        withIntermediateDirectories:YES attributes:nil error:nil];
    logPath = [documents stringByAppendingPathComponent:@"startup-probe.log"];
    logFD = open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (logFD < 0) return 1;
    dup2(logFD, STDOUT_FILENO);
    dup2(logFD, STDERR_FILENO);
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);
    Record([NSString stringWithFormat:@"SESSION iOS %@; %@; pid %d",
        UIDevice.currentDevice.systemVersion, NSProcessInfo.processInfo.operatingSystemVersionString,
        getpid()]);
    return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeDelegate.class));
  }
}
