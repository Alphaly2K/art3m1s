#import <Flutter/Flutter.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <unistd.h>

static int traceFD = -1;
static pthread_mutex_t traceLock = PTHREAD_MUTEX_INITIALIZER;
static NSUInteger platformCalls;

static void Trace(NSString *message) {
  NSData *data = [[NSString stringWithFormat:@"%@ %@\n", NSDate.date, message]
      dataUsingEncoding:NSUTF8StringEncoding];
  pthread_mutex_lock(&traceLock);
  const char *bytes = data.bytes;
  NSUInteger remaining = data.length;
  while (remaining > 0) {
    ssize_t count = write(traceFD, bytes, remaining);
    if (count <= 0) break;
    bytes += count;
    remaining -= count;
  }
  fsync(traceFD);
  pthread_mutex_unlock(&traceLock);
}

void Art3m1sTraceMessage(NSString *message) {
  Trace(message);
}

static void Images(void) {
  for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
    const struct mach_header *header = _dyld_get_image_header(i);
    NSString *uuid = @"unknown";
    if (header->magic == MH_MAGIC_64) {
      const struct load_command *command = (const void *)
          ((const struct mach_header_64 *)header + 1);
      for (uint32_t j = 0; j < header->ncmds; ++j) {
        if (command->cmd == LC_UUID) {
          const struct uuid_command *item = (const void *)command;
          uuid = [[NSUUID alloc] initWithUUIDBytes:item->uuid].UUIDString;
          break;
        }
        command = (const void *)((const char *)command + command->cmdsize);
      }
    }
    Trace([NSString stringWithFormat:@"IMAGE %p %@ %s", header, uuid,
                                     _dyld_get_image_name(i)]);
  }
}

static Method FindMethod(Class cls, SEL selector, char resultType, unsigned arguments) {
  Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
  char *returnType = method ? method_copyReturnType(method) : NULL;
  BOOL valid = returnType && returnType[0] == resultType &&
               method_getNumberOfArguments(method) == arguments + 2;
  free(returnType);
  for (unsigned i = 0; valid && i < arguments; ++i) {
    char *argumentType = method_copyArgumentType(method, i + 2);
    valid = argumentType && argumentType[0] == '@';
    free(argumentType);
  }
  if (!valid) {
    Trace([NSString stringWithFormat:@"HOOK_SKIPPED %@ %@", NSStringFromClass(cls),
                                     NSStringFromSelector(selector)]);
    return NULL;
  }
  return method;
}

static void Install(Class cls, SEL selector, Method method, id block) {
  // Replacing on the requested class also handles inherited implementations
  // without changing the superclass's method table.
  class_replaceMethod(cls, selector, imp_implementationWithBlock(block),
                      method_getTypeEncoding(method));
  Trace([NSString stringWithFormat:@"HOOK %@ %@", NSStringFromClass(cls),
                                   NSStringFromSelector(selector)]);
}

static NSString *Label(Class cls, SEL selector) {
  return [NSString stringWithFormat:@"%@ %@", NSStringFromClass(cls),
                                    NSStringFromSelector(selector)];
}

static void HookVoid0(Class cls, SEL selector) {
  Method method = FindMethod(cls, selector, 'v', 0);
  if (!method) return;
  void (*original)(id, SEL) = (void *)method_getImplementation(method);
  NSString *label = Label(cls, selector);
  Install(cls, selector, method, ^(id self) {
    Trace([@"BEGIN " stringByAppendingString:label]);
    original(self, selector);
    Trace([@"END " stringByAppendingString:label]);
  });
}

static void HookVoid1(Class cls, SEL selector) {
  Method method = FindMethod(cls, selector, 'v', 1);
  if (!method) return;
  void (*original)(id, SEL, id) = (void *)method_getImplementation(method);
  NSString *label = Label(cls, selector);
  Install(cls, selector, method, ^(id self, id argument) {
    Trace([@"BEGIN " stringByAppendingString:label]);
    original(self, selector, argument);
    Trace([@"END " stringByAppendingString:label]);
  });
}

static void HookVoid3(Class cls, SEL selector) {
  Method method = FindMethod(cls, selector, 'v', 3);
  if (!method) return;
  void (*original)(id, SEL, id, id, id) = (void *)method_getImplementation(method);
  NSString *label = Label(cls, selector);
  Install(cls, selector, method, ^(id self, id a, id b, id c) {
    Trace([@"BEGIN " stringByAppendingString:label]);
    original(self, selector, a, b, c);
    Trace([@"END " stringByAppendingString:label]);
  });
}

static void HookBool2(Class cls, SEL selector) {
  Method method = FindMethod(cls, selector, @encode(BOOL)[0], 2);
  if (!method) return;
  BOOL (*original)(id, SEL, id, id) = (void *)method_getImplementation(method);
  NSString *label = Label(cls, selector);
  Install(cls, selector, method, ^BOOL(id self, id a, id b) {
    Trace([@"BEGIN " stringByAppendingString:label]);
    BOOL result = original(self, selector, a, b);
    Trace([NSString stringWithFormat:@"END %@ result=%d", label, result]);
    return result;
  });
}

static void HookEngineRun(void) {
  Class cls = NSClassFromString(@"FlutterEngine");
  SEL selector = @selector(runWithEntrypoint:libraryURI:initialRoute:entrypointArgs:);
  Method method = FindMethod(cls, selector, @encode(BOOL)[0], 4);
  if (!method) return;
  BOOL (*original)(id, SEL, id, id, id, id) = (void *)method_getImplementation(method);
  Install(cls, selector, method, ^BOOL(id self, id a, id b, id c, id d) {
    Trace(@"BEGIN FlutterEngine runWithEntrypoint");
    BOOL result = original(self, selector, a, b, c, d);
    Trace([NSString stringWithFormat:@"END FlutterEngine runWithEntrypoint result=%d", result]);
    return result;
  });
}

static void HookEngineShell(void) {
  Class cls = NSClassFromString(@"FlutterEngine");
  SEL selector = NSSelectorFromString(@"createShell:libraryURI:initialRoute:");
  Method method = FindMethod(cls, selector, @encode(BOOL)[0], 3);
  if (!method) return;
  BOOL (*original)(id, SEL, id, id, id) = (void *)method_getImplementation(method);
  Install(cls, selector, method, ^BOOL(id self, id a, id b, id c) {
    Trace(@"BEGIN FlutterEngine createShell");
    BOOL result = original(self, selector, a, b, c);
    Trace([NSString stringWithFormat:@"END FlutterEngine createShell result=%d", result]);
    return result;
  });
}

static void HookPlatformCalls(void) {
  Class cls = NSClassFromString(@"FlutterMethodChannel");
  SEL selector = @selector(setMethodCallHandler:);
  Method method = FindMethod(cls, selector, 'v', 1);
  if (!method) return;
  void (*original)(id, SEL, FlutterMethodCallHandler) = (void *)method_getImplementation(method);
  Install(cls, selector, method, ^(id self, FlutterMethodCallHandler handler) {
    if (!handler) {
      original(self, selector, nil);
      return;
    }
    original(self, selector, ^(FlutterMethodCall *call, FlutterResult reply) {
      pthread_mutex_lock(&traceLock);
      NSUInteger sequence = ++platformCalls;
      pthread_mutex_unlock(&traceLock);
      // Bound output during normal app use; arguments and results are not logged.
      BOOL record = sequence <= 200;
      if (record) Trace([NSString stringWithFormat:@"METHOD %lu BEGIN %@",
          (unsigned long)sequence, call.method]);
      handler(call, ^(id result) {
        if (record) Trace([NSString stringWithFormat:@"METHOD %lu REPLY %@",
            (unsigned long)sequence, call.method]);
        reply(result);
      });
      if (record) Trace([NSString stringWithFormat:@"METHOD %lu DISPATCHED %@",
          (unsigned long)sequence, call.method]);
    });
  });
}

static void HookPlugins(void) {
  unsigned count = 0;
  Class *classes = objc_copyClassList(&count);
  SEL selector = @selector(registerWithRegistrar:);
  for (unsigned i = 0; i < count; ++i) {
    Class meta = object_getClass(classes[i]);
    unsigned methodCount = 0;
    Method *methods = class_copyMethodList(meta, &methodCount);
    for (unsigned j = 0; j < methodCount; ++j) {
      if (method_getName(methods[j]) == selector) {
        HookVoid1(meta, selector);
        break;
      }
    }
    free(methods);
  }
  free(classes);
}

__attribute__((constructor)) static void StartTrace(void) {
  @autoreleasepool {
    NSString *documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [NSFileManager.defaultManager createDirectoryAtPath:documents
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [documents stringByAppendingPathComponent:@"startup-trace.log"];
    traceFD = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (traceFD < 0) return;
    dup2(traceFD, STDOUT_FILENO);
    dup2(traceFD, STDERR_FILENO);
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);
    Trace([NSString stringWithFormat:@"TRACE_INITIALIZER iOS %@ pid %d bundle %@",
        UIDevice.currentDevice.systemVersion, getpid(), NSBundle.mainBundle.bundleIdentifier]);
    Images();

    Class delegate = NSClassFromString(@"Runner.AppDelegate") ?: NSClassFromString(@"AppDelegate");
    HookBool2(delegate, @selector(application:willFinishLaunchingWithOptions:));
    HookBool2(delegate, @selector(application:didFinishLaunchingWithOptions:));
    HookVoid1(delegate, @selector(didInitializeImplicitFlutterEngine:));
    HookVoid3(NSClassFromString(@"Runner.SceneDelegate"), @selector(scene:willConnectToSession:options:));
    HookVoid0(NSClassFromString(@"FlutterViewController"), @selector(viewDidLoad));
    HookVoid0(NSClassFromString(@"FlutterViewController"),
              NSSelectorFromString(@"performCommonViewControllerInitialization"));
    HookVoid1(object_getClass(NSClassFromString(@"GeneratedPluginRegistrant")),
              @selector(registerWithRegistry:));
    HookEngineRun();
    HookEngineShell();
    HookVoid3(NSClassFromString(@"FlutterEngine"),
              NSSelectorFromString(@"launchEngine:libraryURI:entrypointArgs:"));
    HookPlugins();
    HookPlatformCalls();
    Trace(@"TRACE_HOOKS_READY");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{ Trace(@"MAIN_QUEUE_ALIVE_15S"); });
  }
}
