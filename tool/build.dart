import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = BuildOptions.parse(arguments);
  final project = File.fromUri(Platform.script).parent.parent.absolute;
  final core = _findCore(project);
  final pfs = Directory(
    Platform.environment['PFS_SRC'] ?? '${core.path}/crates/pfs-upk-rust',
  );
  final flutter = _flutterExecutable();
  final metadata = await _buildMetadata(project);
  final secrets = _loadSecrets(project);
  final targets = options.target == 'all'
      ? _hostTargets()
      : <String>[options.target];

  if (options.krkr && !options.signOnly) {
    _requireKrkrSources();
  }

  for (final target in targets) {
    _ensureHostSupports(target);
    if (options.siglus && target != 'macos') {
      throw UsageException('--siglus 目前只支持 macOS 构建');
    }
    stdout.writeln('\n=== Building $target (${options.profile}) ===');
    switch (target) {
      case 'ios':
        await _buildNativeIos(project, core, pfs, options);
      case 'ios-obsolete':
        await _buildIosObsolete(
          project,
          core,
          pfs,
          flutter,
          metadata,
          secrets,
          options,
        );
      case 'macos':
        await _buildMacos(
          project,
          core,
          pfs,
          flutter,
          metadata,
          secrets,
          options,
        );
      case 'android':
        await _buildAndroid(
          project,
          core,
          pfs,
          flutter,
          metadata,
          secrets,
          options,
        );
      case 'windows':
        await _buildWindows(
          project,
          core,
          pfs,
          flutter,
          metadata,
          secrets,
          options,
        );
      case 'linux':
        await _buildLinux(
          project,
          core,
          pfs,
          flutter,
          metadata,
          secrets,
          options,
        );
      default:
        throw UsageException('Unknown target: $target');
    }
  }
}

final class BuildOptions {
  BuildOptions({
    required this.target,
    required this.profile,
    required this.deviceOnly,
    required this.signOnly,
    required this.krkr,
    required this.siglus,
  });

  final String target;
  final String profile;
  final bool deviceOnly;
  final bool signOnly;
  final bool krkr;
  final bool siglus;

  static BuildOptions parse(List<String> arguments) {
    var target = 'all';
    var profile = 'release';
    var deviceOnly = false;
    var signOnly = false;
    var krkr = false;
    var siglus = false;
    for (final argument in arguments) {
      switch (argument) {
        case '--debug':
          profile = 'debug';
        case '--profile':
          profile = 'profile';
        case '--release':
          profile = 'release';
        case '--device-only':
          deviceOnly = true;
        case '--sign-only':
          signOnly = true;
        case '--krkr':
          krkr = true;
        case '--siglus':
          siglus = true;
        case 'all':
        case 'ios':
        case 'ios-obsolete':
        case 'macos':
        case 'android':
        case 'windows':
        case 'linux':
          target = argument;
        case '-h':
        case '--help':
          stdout.writeln(
            'Usage: dart run tool/build.dart '
            '[all|ios|ios-obsolete|macos|android|windows|linux] '
            '[--release|--profile|--debug] [--device-only] [--sign-only] [--krkr] [--siglus]',
          );
          exit(0);
        default:
          throw UsageException('Unknown argument: $argument');
      }
    }
    return BuildOptions(
      target: target,
      profile: profile,
      deviceOnly: deviceOnly,
      signOnly: signOnly,
      krkr: krkr,
      siglus: siglus,
    );
  }
}

final class BuildMetadata {
  const BuildMetadata(this.commit, this.version);
  final String commit;
  final String version;

  List<String> get dartDefines => <String>[
    '--dart-define=GIT_COMMIT=$commit',
    '--dart-define=APP_VERSION=$version',
  ];
}

/// Credentials and upload configuration that must never enter git.
///
/// Resolution order: process environment first, then the untracked
/// `tool/secrets.local.env` file (see `tool/secrets.example.env`).
final class BuildSecrets {
  const BuildSecrets({this.sentryDsn = '', this.sentryAuthToken = ''});

  final String sentryDsn;
  final String sentryAuthToken;

  List<String> get dartDefines => <String>[
    if (sentryDsn.isNotEmpty) '--dart-define=SENTRY_DSN=$sentryDsn',
  ];

  /// Extra environment for the Flutter build process; `sentry_dart_plugin`
  /// picks up `SENTRY_AUTH_TOKEN` for debug-symbol upload.
  Map<String, String> get environment => <String, String>{
    if (sentryAuthToken.isNotEmpty) 'SENTRY_AUTH_TOKEN': sentryAuthToken,
  };
}

BuildSecrets _loadSecrets(Directory project) {
  var values = <String, String>{};
  final file = File('${project.path}/tool/secrets.local.env');
  if (file.existsSync()) {
    for (final rawLine in file.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
  }
  // Environment variables win over the file.
  values = <String, String>{...values, ...Platform.environment};
  return BuildSecrets(
    sentryDsn: values['SENTRY_DSN'] ?? '',
    sentryAuthToken: values['SENTRY_AUTH_TOKEN'] ?? '',
  );
}

final class UsageException implements Exception {
  UsageException(this.message);
  final String message;
  @override
  String toString() => message;
}

void _requireKrkrSources() {
  for (final name in const <String>[
    'KRKRSDL3_SOURCE_DIR',
    'KRKRSDL3_BUILD_DIR',
    'VCPKG_ROOT',
  ]) {
    final path = Platform.environment[name];
    if (path == null || path.isEmpty || !Directory(path).existsSync()) {
      throw StateError('--krkr 需要有效的 $name');
    }
  }
}

Directory _findCore(Directory project) {
  final configured = Platform.environment['CORE_SRC'];
  final candidates = <Directory>[
    if (configured != null) Directory(configured),
    Directory('${project.parent.path}/art3m1s-core'),
    Directory('${Platform.environment['HOME']}/RustroverProjects/art3m1s-core'),
  ];
  return candidates.firstWhere(
    (candidate) => File('${candidate.path}/Cargo.toml').existsSync(),
    orElse: () => throw StateError(
      'art3m1s-core not found; set CORE_SRC to its checkout',
    ),
  );
}

String _flutterExecutable() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) return 'flutter';
  return Platform.isWindows ? '$root\\bin\\flutter.bat' : '$root/bin/flutter';
}

Future<BuildMetadata> _buildMetadata(Directory project) async {
  final commitResult = await Process.run('git', const <String>[
    'rev-parse',
    '--short',
    'HEAD',
  ], workingDirectory: project.path);
  final commit = commitResult.exitCode == 0
      ? '${commitResult.stdout}'.trim()
      : 'unknown';
  final pubspec = File('${project.path}/pubspec.yaml').readAsLinesSync();
  final versionLine = pubspec.firstWhere((line) => line.startsWith('version:'));
  final version = versionLine
      .substring('version:'.length)
      .trim()
      .split('+')
      .first;
  return BuildMetadata(commit, version);
}

List<String> _hostTargets() {
  if (Platform.isMacOS) {
    return const <String>['ios', 'macos', 'android'];
  }
  if (Platform.isWindows) return const <String>['windows', 'android'];
  if (Platform.isLinux) return const <String>['linux', 'android'];
  throw UnsupportedError('Unsupported build host: ${Platform.operatingSystem}');
}

void _ensureHostSupports(String target) {
  final supported = switch (target) {
    'ios' || 'ios-obsolete' || 'macos' => Platform.isMacOS,
    'windows' => Platform.isWindows,
    'linux' => Platform.isLinux,
    'android' => true,
    _ => false,
  };
  if (!supported) {
    throw UnsupportedError(
      '$target cannot be built on ${Platform.operatingSystem}',
    );
  }
}

Future<void> _buildNativeIos(
  Directory project,
  Directory core,
  Directory pfs,
  BuildOptions options,
) async {
  if (options.signOnly) {
    await _signNativeIosAppForTrollStore(project, profile: options.profile);
    return;
  }

  await _buildIosFfmpeg(project, options);

  final rustArgs = <String>[
    options.profile == 'debug' ? '--debug' : '--release',
  ];
  if (options.deviceOnly) {
    rustArgs.add('--device-only');
  }
  if (options.krkr) rustArgs.add('--krkr');
  await _run(
    '${project.path}/scripts/ios_build_rust.sh',
    rustArgs,
    workingDirectory: project,
    environment: <String, String>{'CORE_SRC': core.path, 'PFS_SRC': pfs.path},
  );

  final configuration = options.profile == 'debug' ? 'Debug' : 'Release';
  final derivedData = Directory('${project.path}/build/ios-native/DerivedData');
  final commonArgs = <String>[
    '-project',
    '${project.path}/native/ios/Art3m1sNative/Art3m1sNative.xcodeproj',
    '-scheme',
    'Art3m1sNative',
    '-configuration',
    configuration,
    '-derivedDataPath',
    derivedData.path,
    'CODE_SIGNING_ALLOWED=NO',
  ];

  await _run('xcodebuild', <String>[
    ...commonArgs,
    '-destination',
    'generic/platform=iOS',
    'build',
  ], workingDirectory: project);

  if (!options.deviceOnly) {
    await _run('xcodebuild', <String>[
      ...commonArgs,
      '-destination',
      'generic/platform=iOS Simulator',
      'ARCHS=arm64',
      'build',
    ], workingDirectory: project);
  }

  if (options.krkr) {
    _bundleKrkrIosResources(
      project,
      _nativeIosAppCandidates(project, options.profile),
    );
  }

  await _signNativeIosAppForTrollStore(project, profile: options.profile);
}

Future<void> _buildIosFfmpeg(Directory project, BuildOptions options) async {
  final devicePrefix = Directory(
    '${project.path}/.build/ffmpeg-ios/device/prefix',
  );
  if (_ffmpegIosReady(
    project,
    devicePrefix,
    includeSimulator: !options.deviceOnly,
  )) {
    stdout.writeln('FFmpeg build is up to date, reusing it.');
    return;
  }
  await _run('${project.path}/scripts/build_ffmpeg_ios.sh', <String>[
    if (options.deviceOnly) '--device-only',
  ], workingDirectory: project);
}

bool _ffmpegIosReady(
  Directory project,
  Directory devicePrefix, {
  required bool includeSimulator,
}) {
  const libraries = <String>[
    'avcodec',
    'avformat',
    'avutil',
    'swresample',
    'swscale',
  ];
  final prefixes = <Directory>[
    devicePrefix,
    if (includeSimulator)
      Directory('${project.path}/.build/ffmpeg-ios/simulator/prefix'),
  ];
  for (final prefix in prefixes) {
    for (final name in libraries) {
      if (!File('${prefix.path}/lib/lib$name.dylib').existsSync()) {
        return false;
      }
    }
  }
  final frameworks = Directory('${project.path}/ios/Frameworks');
  for (final name in libraries) {
    if (!Directory('${frameworks.path}/lib$name.xcframework').existsSync()) {
      return false;
    }
  }
  return true;
}

Future<void> _buildIosObsolete(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildSecrets secrets,
  BuildOptions options,
) async {
  if (options.signOnly) {
    await _signIosObsoleteAppForTrollStore(project, profile: options.profile);
    return;
  }
  final args = <String>[options.profile == 'release' ? '--release' : '--debug'];
  if (options.deviceOnly) args.add('--device-only');
  if (options.krkr) args.add('--krkr');
  await _run(
    '${project.path}/scripts/ios_build_rust.sh',
    args,
    workingDirectory: project,
    environment: <String, String>{'CORE_SRC': core.path, 'PFS_SRC': pfs.path},
  );
  await _run(
    flutter,
    <String>[
      'build',
      'ios',
      '--${options.profile}',
      '--no-codesign',
      ...metadata.dartDefines,
      ...secrets.dartDefines,
    ],
    workingDirectory: project,
    environment: secrets.environment,
  );
  if (options.krkr) {
    _bundleKrkrIosResources(
      project,
      _iosObsoleteAppCandidates(project, options.profile),
    );
  }
  await _signIosObsoleteAppForTrollStore(project, profile: options.profile);
}

void _bundleKrkrIosResources(Directory project, List<Directory> apps) {
  final source = File(
    '${project.path}/ios/Frameworks/.ios-framework-build/krkr_host/Res/DroidSansFallback.ttf',
  );
  if (!source.existsSync() || apps.isEmpty) {
    throw StateError('KRKR iOS 上游资源或应用包缺失');
  }
  for (final app in apps) {
    final resources = Directory('${app.path}/Res')..createSync(recursive: true);
    source.copySync('${resources.path}/DroidSansFallback.ttf');
  }
}

Future<void> _buildMacos(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildSecrets secrets,
  BuildOptions options,
) async {
  final krkrSource = Platform.environment['KRKRSDL3_SOURCE_DIR'];
  final ffmpegPrefix = Directory('${project.path}/.build/ffmpeg-macos/prefix');
  if (!_ffmpegMacosReady(ffmpegPrefix)) {
    await _run(
      '${project.path}/scripts/build_ffmpeg_macos.sh',
      const <String>[],
      workingDirectory: project,
    );
  }
  await _run(
    'cargo',
    <String>[
      'build',
      if (options.profile == 'release') '--release',
      '--features',
      options.siglus ? 'ffmpeg,siglus-engine' : 'ffmpeg',
      '--manifest-path',
      '${core.path}/Cargo.toml',
    ],
    workingDirectory: core,
    environment: <String, String>{
      'FFMPEG_DIR': ffmpegPrefix.path,
      if (options.krkr) 'ART3M1S_KRKR_REQUIRE_UPSTREAM': '1',
    },
  );
  await _run('cargo', <String>[
    'build',
    if (options.profile == 'release') '--release',
    '--manifest-path',
    '${pfs.path}/Cargo.toml',
  ], workingDirectory: pfs);

  final suffix = options.profile == 'release' ? 'release' : 'debug';
  File(
    '${core.path}/target/$suffix/libart3m1s_core.dylib',
  ).copySync('${project.path}/libart3m1s_core.dylib');
  File(
    '${pfs.path}/target/$suffix/libpfs_upk.dylib',
  ).copySync('${project.path}/libpfs_upk.dylib');
  for (final name in const <String>[
    'libavcodec.62.dylib',
    'libavformat.62.dylib',
    'libavutil.60.dylib',
    'libswresample.6.dylib',
    'libswscale.9.dylib',
  ]) {
    final source = File('${ffmpegPrefix.path}/lib/$name');
    if (!source.existsSync()) {
      throw StateError('missing FFmpeg library: ${source.path}');
    }
    source.copySync('${project.path}/$name');
  }
  await _run('${project.path}/scripts/build_angle.sh', const <String>[
    'macos',
  ], workingDirectory: project);
  await _run(
    flutter,
    <String>[
      'build',
      'macos',
      '--${options.profile}',
      ...metadata.dartDefines,
      ...secrets.dartDefines,
    ],
    workingDirectory: project,
    environment: secrets.environment,
  );
  if (options.krkr) {
    await _bundleKrkrMacos(project, core, options.profile, krkrSource!);
  }
}

bool _ffmpegMacosReady(Directory prefix) => const <String>[
  'libavcodec.62.dylib',
  'libavformat.62.dylib',
  'libavutil.60.dylib',
  'libswresample.6.dylib',
  'libswscale.9.dylib',
].every((name) => File('${prefix.path}/lib/$name').existsSync());

Future<void> _bundleKrkrMacos(
  Directory project,
  Directory core,
  String profile,
  String upstreamSource,
) async {
  final suffix = profile == 'release' ? 'release' : 'debug';
  final builds = Directory('${core.path}/target/$suffix/build');
  final hosts =
      builds
          .listSync()
          .whereType<Directory>()
          .where(
            (dir) => dir.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('art3m1s-krkr-'),
          )
          .map(
            (dir) => File(
              '${dir.path}/out/native-upstream/libart3m1s_krkr_host.dylib',
            ),
          )
          .where((file) => file.existsSync())
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  if (hosts.isEmpty) {
    throw StateError('未找到真实 KRKR native-upstream 构建产物');
  }
  final nativeHost = hosts.first;
  final nativeResources = Directory('${nativeHost.parent.path}/Res');
  if (!nativeResources.existsSync()) {
    throw StateError('KRKR native-upstream 缺少 Res 资源目录');
  }

  final configuration = profile[0].toUpperCase() + profile.substring(1);
  final app = Directory(
    '${project.path}/build/macos/Build/Products/$configuration/art3m1s.app',
  );
  if (!app.existsSync()) throw StateError('未找到 macOS 应用包: ${app.path}');
  final executableDir = Directory('${app.path}/Contents/MacOS');
  final bundledCore = File('${executableDir.path}/libart3m1s_core.dylib');
  final resourceDir = Directory('${app.path}/Contents/Resources/krkr')
    ..createSync(recursive: true);
  final bundledHost = nativeHost.copySync(
    '${executableDir.path}/libart3m1s_krkr_host.dylib',
  );
  await _run('/usr/bin/ditto', <String>[
    nativeResources.path,
    '${resourceDir.path}/Res',
  ], workingDirectory: project);
  File(
    '$upstreamSource/LICENSE',
  ).copySync('${resourceDir.path}/LICENSE-KRKRSDL3.txt');
  File(
    '${core.path}/crates/art3m1s-krkr/THIRD_PARTY_NOTICES.md',
  ).copySync('${resourceDir.path}/THIRD_PARTY_NOTICES.md');
  await _run('/usr/bin/install_name_tool', <String>[
    '-add_rpath',
    '@loader_path/../Frameworks',
    bundledCore.path,
  ], workingDirectory: project);
  await _run('/usr/bin/codesign', <String>[
    '--force',
    '--sign',
    '-',
    '--timestamp=none',
    bundledCore.path,
  ], workingDirectory: project);
  await _run('/usr/bin/codesign', <String>[
    '--force',
    '--sign',
    '-',
    '--timestamp=none',
    bundledHost.path,
  ], workingDirectory: project);
  await _run('/usr/bin/codesign', <String>[
    '--force',
    '--sign',
    '-',
    '--preserve-metadata=entitlements',
    '--timestamp=none',
    app.path,
  ], workingDirectory: project);
  final archive = '${app.parent.path}/art3m1s-krkr-macos-$profile.zip';
  await _run('/usr/bin/ditto', <String>[
    '-c',
    '-k',
    '--sequesterRsrc',
    '--keepParent',
    app.path,
    archive,
  ], workingDirectory: project);
  stdout.writeln('KRKR macOS package: $archive');
}

Future<void> _buildAndroid(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildSecrets secrets,
  BuildOptions options,
) async {
  final output = Directory('${project.path}/android/app/src/main/jniLibs');
  output.createSync(recursive: true);
  for (final crate in <Directory>[core, pfs]) {
    final isCore = crate.path == core.path;
    await _run(
      'cargo',
      <String>[
        'ndk',
        '-t',
        'arm64-v8a',
        '-o',
        output.path,
        'build',
        if (options.profile == 'release') '--release',
        // Android defaults omit KRKR; --krkr opts into the real upstream host.
        if (isCore) ...<String>[
          '--no-default-features',
          '--features',
          'gl-backend,metal-backend,vulkan-backend,experimental-eluna,rfvp-engine${options.krkr ? ',krkr-engine' : ''}',
        ],
        '--manifest-path',
        '${crate.path}/Cargo.toml',
      ],
      workingDirectory: crate,
      environment: <String, String>{
        if (isCore && options.krkr) 'ART3M1S_KRKR_REQUIRE_UPSTREAM': '1',
      },
    );
  }
  File? stagedFont;
  String? krkrJavaDir;
  if (options.krkr) {
    final host = _findKrkrHost(
      core,
      'target/aarch64-linux-android/${options.profile == 'release' ? 'release' : 'debug'}/build',
      'libart3m1s_krkr_host.so',
    );
    host.copySync('${output.path}/arm64-v8a/libart3m1s_krkr_host.so');
    final installed = _krkrVcpkgInstalled(host);
    final sdl = File('$installed/arm64-android/lib/libSDL3.so');
    if (!sdl.existsSync()) {
      throw StateError('KRKR Android 缺少 libSDL3.so: ${sdl.path}');
    }
    sdl.copySync('${output.path}/arm64-v8a/libSDL3.so');
    // SDL's JNI ABI is versioned together with libSDL3.so. Never use the
    // KRKRSDL3 checkout's copied Java sources: they can be a different SDL.
    final upstreamJava = _krkrSdl3JavaSource(installed);
    final stagedJava = Directory(
      '${project.path}/.build/krkr-android-java/org/libsdl/app',
    )..createSync(recursive: true);
    for (final file in upstreamJava.listSync().whereType<File>()) {
      if (!file.path.endsWith('.java')) continue;
      final destination = File(
        '${stagedJava.path}/${file.uri.pathSegments.last}',
      );
      if (file.uri.pathSegments.last == 'SDLActivity.java') {
        destination.writeAsStringSync(
          file
              .readAsStringSync()
              .replaceAll(
                'import androidx.appcompat.app.AppCompatActivity;',
                '',
              )
              .replaceAll('extends AppCompatActivity', 'extends Activity'),
        );
      } else {
        file.copySync(destination.path);
      }
    }
    krkrJavaDir = '${project.path}/.build/krkr-android-java';
    final asset = File(
      '${project.path}/android/app/src/main/assets/DroidSansFallback.ttf',
    );
    if (asset.existsSync()) {
      throw StateError('KRKR asset 已存在，拒绝覆盖: ${asset.path}');
    }
    asset.parent.createSync(recursive: true);
    File('${host.parent.path}/Res/DroidSansFallback.ttf').copySync(asset.path);
    stagedFont = asset;
  }
  final buildEnvironment = <String, String>{...secrets.environment};
  if (krkrJavaDir != null) {
    buildEnvironment['ART3M1S_KRKR_ANDROID_JAVA_DIR'] = krkrJavaDir;
  }
  try {
    await _run(
      flutter,
      <String>[
        'build',
        'apk',
        '--${options.profile}',
        '--target-platform=android-arm64',
        ...metadata.dartDefines,
        ...secrets.dartDefines,
      ],
      workingDirectory: project,
      environment: buildEnvironment,
    );
  } finally {
    stagedFont?.deleteSync();
  }
}

Future<void> _buildWindows(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildSecrets secrets,
  BuildOptions options,
) async {
  await _buildHostRust(core, pfs, options.profile, krkr: options.krkr);
  await _run(
    flutter,
    <String>[
      'build',
      'windows',
      '--${options.profile}',
      ...metadata.dartDefines,
      ...secrets.dartDefines,
    ],
    workingDirectory: project,
    environment: secrets.environment,
  );
  final bundle = _findDirectory(
    Directory('${project.path}/build/windows'),
    options.profile == 'release' ? 'Release' : 'Debug',
  );
  final suffix = options.profile == 'release' ? 'release' : 'debug';
  File(
    '${core.path}/target/$suffix/art3m1s_core.dll',
  ).copySync('${bundle.path}/art3m1s_core.dll');
  File(
    '${pfs.path}/target/$suffix/pfs_upk.dll',
  ).copySync('${bundle.path}/pfs_upk.dll');
  if (options.krkr) {
    _bundleKrkrDesktop(core, bundle, profile: options.profile, windows: true);
  }
}

Future<void> _buildLinux(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildSecrets secrets,
  BuildOptions options,
) async {
  await _buildHostRust(core, pfs, options.profile, krkr: options.krkr);
  await _run(
    flutter,
    <String>[
      'build',
      'linux',
      '--${options.profile}',
      ...metadata.dartDefines,
      ...secrets.dartDefines,
    ],
    workingDirectory: project,
    environment: secrets.environment,
  );
  final bundle = _findDirectory(
    Directory('${project.path}/build/linux'),
    'bundle',
  );
  final lib = Directory('${bundle.path}/lib')..createSync(recursive: true);
  final suffix = options.profile == 'release' ? 'release' : 'debug';
  File(
    '${core.path}/target/$suffix/libart3m1s_core.so',
  ).copySync('${lib.path}/libart3m1s_core.so');
  File(
    '${pfs.path}/target/$suffix/libpfs_upk.so',
  ).copySync('${lib.path}/libpfs_upk.so');
  if (options.krkr) {
    _bundleKrkrDesktop(
      core,
      lib,
      profile: options.profile,
      windows: false,
      resourceRoot: bundle,
    );
  }
}

Future<void> _buildHostRust(
  Directory core,
  Directory pfs,
  String profile, {
  required bool krkr,
}) async {
  for (final crate in <Directory>[core, pfs]) {
    await _run(
      'cargo',
      <String>[
        'build',
        if (profile == 'release') '--release',
        '--manifest-path',
        '${crate.path}/Cargo.toml',
      ],
      workingDirectory: crate,
      environment: <String, String>{
        if (krkr && crate.path == core.path)
          'ART3M1S_KRKR_REQUIRE_UPSTREAM': '1',
      },
    );
  }
}

void _bundleKrkrDesktop(
  Directory core,
  Directory bundle, {
  required String profile,
  required bool windows,
  Directory? resourceRoot,
}) {
  final suffix = profile == 'release' ? 'release' : 'debug';
  final name = windows ? 'art3m1s_krkr_host.dll' : 'libart3m1s_krkr_host.so';
  final host = _findKrkrHost(core, 'target/$suffix/build', name);
  host.copySync('${bundle.path}/$name');
  final resources = Directory('${host.parent.path}/Res');
  if (!File('${resources.path}/DroidSansFallback.ttf').existsSync()) {
    throw StateError('KRKR native-upstream 缺少 Res 资源目录');
  }
  final resourceOutput = Directory('${(resourceRoot ?? bundle).path}/Res')
    ..createSync(recursive: true);
  File(
    '${resources.path}/DroidSansFallback.ttf',
  ).copySync('${resourceOutput.path}/DroidSansFallback.ttf');
  final source = Platform.environment['KRKRSDL3_SOURCE_DIR']!;
  File(
    '$source/LICENSE',
  ).copySync('${(resourceRoot ?? bundle).path}/LICENSE-KRKRSDL3.txt');
  File(
    '${core.path}/crates/art3m1s-krkr/THIRD_PARTY_NOTICES.md',
  ).copySync('${(resourceRoot ?? bundle).path}/THIRD_PARTY_NOTICES.md');
  if (windows) {
    final binaries = Directory('${_krkrVcpkgInstalled(host)}/x64-windows/bin');
    if (!binaries.existsSync()) throw StateError('KRKR Windows vcpkg bin 缺失');
    for (final file in binaries.listSync().whereType<File>()) {
      final basename = file.uri.pathSegments.last;
      if (basename.toLowerCase().endsWith('.dll')) {
        file.copySync('${bundle.path}/$basename');
      }
    }
  }
}

File _findKrkrHost(Directory core, String buildPath, String name) {
  final builds = Directory('${core.path}/$buildPath');
  final hosts =
      builds
          .listSync()
          .whereType<Directory>()
          .where(
            (dir) => dir.uri.pathSegments
                .where((segment) => segment.isNotEmpty)
                .last
                .startsWith('art3m1s-krkr-'),
          )
          .map((dir) => File('${dir.path}/out/native-upstream/$name'))
          .where((file) => file.existsSync())
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  if (hosts.isEmpty) throw StateError('未找到真实 KRKR native-upstream 构建产物: $name');
  return hosts.first;
}

String _krkrVcpkgInstalled(File host) {
  final cache = File('${host.parent.path}/CMakeCache.txt');
  if (!cache.existsSync()) throw StateError('KRKR CMakeCache.txt 缺失');
  for (final line in cache.readAsLinesSync()) {
    if (line.startsWith('VCPKG_INSTALLED_DIR:PATH=')) {
      return line.substring('VCPKG_INSTALLED_DIR:PATH='.length);
    }
  }
  throw StateError('KRKR vcpkg installed dir 未记录在 CMake cache');
}

Directory _krkrSdl3JavaSource(String installed) {
  final vcpkg = Platform.environment['VCPKG_ROOT']!;
  final packageInfo = Directory('$installed/vcpkg/info');
  if (!packageInfo.existsSync()) {
    throw StateError('SDL3 vcpkg 安装元数据缺失: ${packageInfo.path}');
  }
  final versions = packageInfo
      .listSync()
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where(
        (name) =>
            name.startsWith('sdl3_') && name.endsWith('_arm64-android.list'),
      )
      .map(
        (name) => name.substring(
          'sdl3_'.length,
          name.length - '_arm64-android.list'.length,
        ),
      )
      .toList();
  if (versions.length != 1) {
    throw StateError('无法确定已安装 SDL3 arm64-android 的唯一版本');
  }
  final version = versions.single;
  final sources = Directory('$vcpkg/buildtrees/sdl3/src');
  if (!sources.existsSync()) {
    throw StateError('SDL3 vcpkg 源码缺失；请先安装 arm64-android 依赖');
  }
  final activities = sources
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where(
        (file) =>
            file.path.contains(version) &&
            file.path.endsWith(
              '/android-project/app/src/main/java/org/libsdl/app/SDLActivity.java',
            ),
      )
      .toList();
  if (activities.isEmpty) {
    throw StateError('找不到与 libSDL3.so 同版本 ($version) 的 Android Java 源码');
  }
  return activities.first.parent;
}

Directory _findDirectory(Directory root, String basename) {
  final matches = root
      .listSync(recursive: true, followLinks: false)
      .whereType<Directory>()
      .where(
        (directory) =>
            directory.uri.pathSegments
                .where((segment) => segment.isNotEmpty)
                .last ==
            basename,
      )
      .toList();
  if (matches.isEmpty) {
    throw StateError('$basename output directory not found under ${root.path}');
  }
  matches.sort((a, b) => a.path.length.compareTo(b.path.length));
  return matches.first;
}

List<Directory> _nativeIosAppCandidates(Directory project, String profile) {
  final configuration = profile == 'debug' ? 'Debug' : 'Release';
  final path =
      '${project.path}/build/ios-native/DerivedData/Build/Products/'
      '$configuration-iphoneos/Art3m1sNative.app';
  return Directory(path).existsSync() ? <Directory>[Directory(path)] : const [];
}

Future<void> _signNativeIosAppForTrollStore(
  Directory project, {
  required String profile,
}) async {
  final apps = _nativeIosAppCandidates(project, profile);
  if (apps.isEmpty) {
    throw StateError(
      'No $profile Art3m1sNative.app found under '
      '${project.path}/build/ios-native/DerivedData',
    );
  }
  await _run('/usr/bin/python3', <String>[
    '${project.path}/tool/package_ios_ipa.py',
    apps.first.path,
    '${project.path}/build/ios/Art3m1s-trollstore.ipa',
  ], workingDirectory: project);
}

List<Directory> _iosObsoleteAppCandidates(Directory project, String profile) {
  final ordered = <String>[
    if (profile == 'profile')
      '${project.path}/build/ios/Profile-iphoneos/Runner.app'
    else if (profile == 'debug')
      '${project.path}/build/ios/Debug-iphoneos/Runner.app'
    else
      '${project.path}/build/ios/Release-iphoneos/Runner.app',
    '${project.path}/build/ios/iphoneos/Runner.app',
  ];
  final seen = <String>{};
  return [
    for (final path in ordered)
      if (seen.add(path) && Directory(path).existsSync()) Directory(path),
  ];
}

Future<void> _signIosObsoleteAppForTrollStore(
  Directory project, {
  required String profile,
}) async {
  final apps = _iosObsoleteAppCandidates(project, profile);
  if (apps.isEmpty) {
    throw StateError(
      'No $profile Runner.app found under ${project.path}/build/ios',
    );
  }
  await _run('/usr/bin/python3', <String>[
    '${project.path}/tool/package_ios_ipa.py',
    apps.first.path,
    '${project.path}/build/ios-obsolete/Art3m1s-obsolete-trollstore.ipa',
  ], workingDirectory: project);
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
  Map<String, String> environment = const <String, String>{},
}) async {
  stdout.writeln('+ $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: <String, String>{...Platform.environment, ...environment},
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'exit code $exitCode',
      exitCode,
    );
  }
}
