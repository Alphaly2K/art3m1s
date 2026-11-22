import 'dart:ffi';
import 'dart:io';

DynamicLibrary openEngineCoreLibrary() {
  final configured = Platform.environment['ART3M1S_CORE_LIBRARY'];
  if (configured != null && configured.isNotEmpty) {
    return DynamicLibrary.open(configured);
  }
  final name = Platform.isWindows
      ? 'art3m1s_core.dll'
      : Platform.isMacOS
      ? 'libart3m1s_core.dylib'
      : 'libart3m1s_core.so';
  final executable = File(Platform.resolvedExecutable).parent;
  final candidates = Platform.isIOS
      ? [
          '@rpath/art3m1s_core.framework/art3m1s_core',
          '@executable_path/Frameworks/art3m1s_core.framework/art3m1s_core',
        ]
      : [
          '${executable.path}/$name',
          if (Platform.isLinux) '${executable.path}/lib/$name',
          if (Platform.isMacOS) '${executable.parent.path}/Frameworks/$name',
          name,
        ];
  Object? lastError;
  for (final candidate in candidates) {
    try {
      return DynamicLibrary.open(candidate);
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('Cannot load engine core: $lastError');
}

DynamicLibrary openKatzeHostLibrary() {
  final configured = Platform.environment['KATZE_GAME_HOST'];
  if (configured != null && configured.isNotEmpty) {
    return DynamicLibrary.open(configured);
  }
  final executable = File(Platform.resolvedExecutable).parent;
  final name = Platform.isWindows
      ? 'katze_system2_example_host.dll'
      : Platform.isMacOS
      ? 'libkatze_system2_example_host.dylib'
      : 'libkatze_system2_example_host.so';
  final candidates = [
    '${executable.path}/$name',
    if (Platform.isMacOS) '${executable.parent.path}/Frameworks/$name',
    if (Platform.isLinux) '${executable.path}/lib/$name',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return DynamicLibrary.open(candidate);
  }
  throw StateError('CatSystem2 host library is unavailable');
}
