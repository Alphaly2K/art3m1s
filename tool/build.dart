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
  final targets = options.target == 'all'
      ? _hostTargets()
      : <String>[options.target];

  for (final target in targets) {
    _ensureHostSupports(target);
    stdout.writeln('\n=== Building $target (${options.profile}) ===');
    switch (target) {
      case 'ios':
        await _buildIos(project, core, pfs, flutter, metadata, options);
      case 'macos':
        await _buildMacos(project, core, pfs, flutter, metadata, options);
      case 'android':
        await _buildAndroid(project, core, pfs, flutter, metadata, options);
      case 'windows':
        await _buildWindows(project, core, pfs, flutter, metadata, options);
      case 'linux':
        await _buildLinux(project, core, pfs, flutter, metadata, options);
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
  });

  final String target;
  final String profile;
  final bool deviceOnly;

  static BuildOptions parse(List<String> arguments) {
    var target = 'all';
    var profile = 'release';
    var deviceOnly = false;
    for (final argument in arguments) {
      switch (argument) {
        case '--debug':
          profile = 'debug';
        case '--release':
          profile = 'release';
        case '--device-only':
          deviceOnly = true;
        case 'all':
        case 'ios':
        case 'macos':
        case 'android':
        case 'windows':
        case 'linux':
          target = argument;
        case '-h':
        case '--help':
          stdout.writeln(
            'Usage: dart run tool/build.dart '
            '[all|ios|macos|android|windows|linux] '
            '[--release|--debug] [--device-only]',
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

final class UsageException implements Exception {
  UsageException(this.message);
  final String message;
  @override
  String toString() => message;
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
  if (Platform.isMacOS) return const <String>['ios', 'macos', 'android'];
  if (Platform.isWindows) return const <String>['windows', 'android'];
  if (Platform.isLinux) return const <String>['linux', 'android'];
  throw UnsupportedError('Unsupported build host: ${Platform.operatingSystem}');
}

void _ensureHostSupports(String target) {
  final supported = switch (target) {
    'ios' || 'macos' => Platform.isMacOS,
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

Future<void> _buildIos(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildOptions options,
) async {
  final args = <String>[options.profile == 'release' ? '--release' : '--debug'];
  if (options.deviceOnly) args.add('--device-only');
  await _run(
    '${project.path}/scripts/ios_build_rust.sh',
    args,
    workingDirectory: project,
    environment: <String, String>{'CORE_SRC': core.path, 'PFS_SRC': pfs.path},
  );
  await _run(flutter, <String>[
    'build',
    'ios',
    '--${options.profile}',
    '--no-codesign',
    ...metadata.dartDefines,
  ], workingDirectory: project);
}

Future<void> _buildMacos(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildOptions options,
) async {
  await _buildHostRust(core, pfs, options.profile);
  final suffix = options.profile == 'release' ? 'release' : 'debug';
  File(
    '${core.path}/target/$suffix/libart3m1s_core.dylib',
  ).copySync('${project.path}/libart3m1s_core.dylib');
  File(
    '${pfs.path}/target/$suffix/libpfs_upk.dylib',
  ).copySync('${project.path}/libpfs_upk.dylib');
  await _run('${project.path}/scripts/build_angle.sh', const <String>[
    'macos',
  ], workingDirectory: project);
  await _run(flutter, <String>[
    'build',
    'macos',
    '--${options.profile}',
    ...metadata.dartDefines,
  ], workingDirectory: project);
}

Future<void> _buildAndroid(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildOptions options,
) async {
  final output = Directory('${project.path}/android/app/src/main/jniLibs');
  output.createSync(recursive: true);
  for (final crate in <Directory>[core, pfs]) {
    await _run('cargo', <String>[
      'ndk',
      '-t',
      'arm64-v8a',
      '-o',
      output.path,
      'build',
      if (options.profile == 'release') '--release',
      '--manifest-path',
      '${crate.path}/Cargo.toml',
    ], workingDirectory: crate);
  }
  await _run(flutter, <String>[
    'build',
    'apk',
    '--${options.profile}',
    '--target-platform=android-arm64',
    ...metadata.dartDefines,
  ], workingDirectory: project);
}

Future<void> _buildWindows(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildOptions options,
) async {
  await _buildHostRust(core, pfs, options.profile);
  await _run(flutter, <String>[
    'build',
    'windows',
    '--${options.profile}',
    ...metadata.dartDefines,
  ], workingDirectory: project);
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
}

Future<void> _buildLinux(
  Directory project,
  Directory core,
  Directory pfs,
  String flutter,
  BuildMetadata metadata,
  BuildOptions options,
) async {
  await _buildHostRust(core, pfs, options.profile);
  await _run(flutter, <String>[
    'build',
    'linux',
    '--${options.profile}',
    ...metadata.dartDefines,
  ], workingDirectory: project);
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
}

Future<void> _buildHostRust(
  Directory core,
  Directory pfs,
  String profile,
) async {
  for (final crate in <Directory>[core, pfs]) {
    await _run('cargo', <String>[
      'build',
      if (profile == 'release') '--release',
      '--manifest-path',
      '${crate.path}/Cargo.toml',
    ], workingDirectory: crate);
  }
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
