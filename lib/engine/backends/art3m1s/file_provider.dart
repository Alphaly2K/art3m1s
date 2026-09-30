import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../services/logger.dart';
import 'core_api.dart';
import 'environment_patch.dart';
import 'project_vfs.dart';

/// Artemis 宿主侧资源入口：解包工程与归档工程统一走 [ProjectVfs]。
///
/// 优先级为 解包目录 > 大 id 分卷 > 小 id 分卷，存档与运行期 override 排在最前。
/// core 侧挂载时使用同一套优先级（挂载 PFS 会让归档父目录成为 sidecar 覆盖层），
/// 避免宿主与引擎两套读取逻辑分叉。
class FileProvider {
  static CoreApiV1? _coreApi;
  static Pointer<Void>? _resources;
  static bool _ownsResources = false;
  static ProjectVfs? _vfs;
  static String _archiveEncoding = 'Shift_JIS';
  static bool _environmentPatchEnabled = false;
  static final Map<String, Uint8List> _environmentPatchCache = {};

  /// 存档读写基准目录（应用沙箱内）。core 传相对路径（如
  /// `savedata/save0001.dat`），一律拼到此目录下落盘/读取。
  static String? _saveDir;

  /// 当前工程是否叠加了 PFS 层（解包目录里带分卷的混合包也算）。
  static bool get hasArchiveLayers => _vfs?.hasArchiveLayers ?? false;

  static void setSaveDir(String dir) {
    _saveDir = dir;
    final api = _coreApi;
    final resources = _resources;
    if (api != null && resources != null) {
      final ptr = dir.toNativeUtf8();
      try {
        api.fsSetSaveDir(resources, ptr);
      } finally {
        malloc.free(ptr);
      }
    }
  }

  /// 归档旁的分卷候选（`game.pfs`、`game.pfs.000`…），AppleDouble 已排除。
  static List<String> listArchiveCandidates(String archivePath) =>
      ProjectVfs.listArchiveCandidatesIn(File(archivePath).parent.path);

  /// 统一打开入口：解包目录或 PFS 归档。
  static void openProject(
    String path, {
    required bool isArchive,
    String archiveEncoding = 'Shift_JIS',
    bool environmentPatchEnabled = false,
  }) {
    if (isArchive) {
      openPfs(
        path,
        archiveEncoding: archiveEncoding,
        environmentPatchEnabled: environmentPatchEnabled,
      );
      return;
    }
    openDirectory(
      path,
      archiveEncoding: archiveEncoding,
      environmentPatchEnabled: environmentPatchEnabled,
    );
  }

  static void openPfs(
    String archivePath, {
    String archiveEncoding = 'Shift_JIS',
    bool environmentPatchEnabled = false,
  }) {
    close();
    _archiveEncoding = archiveEncoding;
    _environmentPatchEnabled = environmentPatchEnabled;
    _vfs = ProjectVfs.openArchive(archivePath, charset: archiveEncoding);
  }

  /// 打开解包工程。工程根目录里若带 `.pfs` 分卷（Tyranor 等打包器的混合目录），
  /// 会自动按优先级叠加成归档层，散装文件仍然优先。
  static void openDirectory(
    String root, {
    String archiveEncoding = 'Shift_JIS',
    bool environmentPatchEnabled = false,
    bool includeInnerArchives = true,
  }) {
    close();
    _archiveEncoding = archiveEncoding;
    _environmentPatchEnabled = environmentPatchEnabled;
    _vfs = ProjectVfs.openDirectory(
      root,
      charset: archiveEncoding,
      includeInnerArchives: includeInnerArchives,
    );
  }

  static Uint8List? readFile(String path) => _lookup(path);

  static List<String> listFiles({String? extension}) =>
      _vfs?.listFiles(extension: extension) ?? const <String>[];

  static void close() {
    final api = _coreApi;
    final resources = _resources;
    if (api != null && resources != null && resources != nullptr) {
      api.fsClear(resources);
      if (_ownsResources) {
        api.destroyResources(resources);
      }
    }
    _coreApi = null;
    _resources = null;
    _ownsResources = false;
    _closeHostMount();
  }

  /// Leaves the mounted native resource handle owned by its EngineRuntime and
  /// drops only FileProvider's process-global staging state.
  ///
  /// Each resident game has its own native resources. Clearing that handle
  /// while another game is being prepared would otherwise unmount the frozen
  /// session's files.
  static void detachCoreMount() {
    _coreApi = null;
    _resources = null;
    _ownsResources = false;
    _closeHostMount();
  }

  static void _closeHostMount() {
    _vfs?.close();
    _vfs = null;
    _archiveEncoding = 'Shift_JIS';
    _saveDir = null;
    _environmentPatchEnabled = false;
    _environmentPatchCache.clear();
  }

  static Uint8List? _lookup(String path) {
    final saveFile = _saveFile(path);
    if (saveFile != null && saveFile.existsSync()) {
      return saveFile.readAsBytesSync();
    }
    final patched = _patchedResource(path);
    if (patched != null) return patched;
    return _readVfs(path);
  }

  static Uint8List? _readVfs(String path) => _vfs?.readFile(path);

  static Uint8List? _patchedResource(String path) {
    if (!_environmentPatchEnabled) return null;

    final normalized = EnvironmentPatch.normalizePath(path);
    if (normalized.isEmpty) return null;
    final cached = _environmentPatchCache[normalized];
    if (cached != null) return cached;

    final virtual = EnvironmentPatch.virtualFile(normalized);
    if (virtual != null) {
      _environmentPatchCache[normalized] = virtual;
      Log.info('[EnvironmentPatch] 覆盖资源: $normalized');
      return virtual;
    }
    if (!EnvironmentPatch.canTransform(normalized)) return null;

    final original = _readVfs(path);
    if (original == null) return null;
    final transformed = EnvironmentPatch.transform(normalized, original);
    _environmentPatchCache[normalized] = transformed;
    if (!identical(transformed, original)) {
      Log.info('[EnvironmentPatch] 修补启动脚本: $normalized');
    }
    return transformed;
  }

  /// 把 core 传来的脚本相对路径解析为沙箱内的存档文件。
  static File? _saveFile(String path) {
    if (_saveDir == null) return null;
    final rel = ProjectVfs.normalizeRelativePath(path);
    if (rel == null) {
      Log.warn('[FileProvider] 非法存档路径: $path');
      return null;
    }
    return File(
      '$_saveDir${Platform.pathSeparator}'
      '${rel.replaceAll('/', Platform.pathSeparator)}',
    );
  }

  static Map<String, Uint8List> _coreOverrides() {
    if (!_environmentPatchEnabled) return const {};
    final overrides = EnvironmentPatch.virtualFiles();
    final original = _readVfs('system/first.iet');
    if (original != null) {
      final transformed = EnvironmentPatch.transform(
        'system/first.iet',
        original,
      );
      if (!identical(transformed, original)) {
        overrides['system/first.iet'] = transformed;
      }
    }
    return overrides;
  }

  static void mountCore(
    DynamicLibrary lib, {
    CoreApiV1? coreApi,
    Pointer<Void>? resources,
  }) {
    final api = coreApi ?? CoreApiV1.tryLoad(lib);
    if (api == null) {
      throw StateError('core 缺少 art3m1s_get_api_v1，拒绝使用旧文件 ABI');
    }
    final ownsResources = resources == null;
    final resourceHandle = resources ?? api.createResources();
    if (resourceHandle == nullptr) {
      throw StateError('core 创建资源句柄失败');
    }
    api.fsClear(resourceHandle);
    _mountVfs(api, resourceHandle);
    api.fsClearOverrides(resourceHandle);
    for (final entry in _coreOverrides().entries) {
      final path = entry.key.toNativeUtf8();
      final data = entry.value;
      final bytes = malloc.allocate<Uint8>(data.length);
      try {
        bytes.asTypedList(data.length).setAll(0, data);
        if (api.fsSetOverride(resourceHandle, path, bytes, data.length) == 0) {
          throw StateError('set core override failed: ${entry.key}');
        }
      } finally {
        malloc.free(path);
        malloc.free(bytes);
      }
    }
    if (_saveDir case final saveDir?) {
      final path = saveDir.toNativeUtf8();
      try {
        if (api.fsSetSaveDir(resourceHandle, path) == 0) {
          throw StateError('set core save directory failed: $saveDir');
        }
      } finally {
        malloc.free(path);
      }
    }
    _coreApi = api;
    _resources = resourceHandle;
    _ownsResources = ownsResources;
  }

  /// 挂载顺序即优先级：core 的 `resources_mount_pfs` 把归档父目录当作最高优先的
  /// sidecar 层，并在多个归档之间让后挂载者胜出，正好对应
  /// 解包目录 > 大 id 分卷 > 小 id 分卷。
  static void _mountVfs(CoreApiV1 api, Pointer<Void> resources) {
    final vfs = _vfs;
    final archiveBase = vfs?.archiveBasePath;
    if (archiveBase != null) {
      final path = archiveBase.toNativeUtf8();
      final encoding = _archiveEncoding.toNativeUtf8();
      var mounted = false;
      try {
        mounted = api.fsMountPfs(resources, path, encoding) != 0;
      } finally {
        malloc.free(path);
        malloc.free(encoding);
      }
      if (mounted) return;
      Log.warn('[FileProvider] PFS 挂载失败，回退目录挂载: $archiveBase');
    }
    final root = vfs?.directoryRoot;
    if (root == null) {
      throw StateError('FileProvider has no mounted resource root');
    }
    final path = root.toNativeUtf8();
    try {
      if (api.fsMountDirectory(resources, path) == 0) {
        throw StateError('mount directory failed: $root');
      }
    } finally {
      malloc.free(path);
    }
  }
}
