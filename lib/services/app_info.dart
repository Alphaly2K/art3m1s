import 'package:package_info_plus/package_info_plus.dart';

/// 应用版本信息的单一来源，避免在各处硬编码版本串（改一次 pubspec 即全局生效）。
///
/// - **版本名**（如 `1.1.0-0.2.0c`）：从 pubspec 经 package_info 读，`init()` 后同步可用。
/// - **构建号 = git 提交短哈希**：构建时经 `--dart-define=GIT_COMMIT=$(git rev-parse
///   --short HEAD)` 注入（**不写进 pubspec**）。未注入时留空、只显示版本名。
///   便捷脚本见 `tool/run.sh`。
class AppInfo {
  AppInfo._();

  /// 应用 logo 资源路径（关于页徽标等复用；与平台 AppIcon 同一张图）。
  static const String logoAsset = 'assets/branding/art3m1s-logo-v1.png';

  static PackageInfo? _info;

  /// 构建时注入的 git 提交短哈希；未注入时为空串。
  static const String commit = String.fromEnvironment(
    'GIT_COMMIT',
    defaultValue: '',
  );

  /// 构建时从 pubspec 注入的完整版本名（见 tool/run.sh）。
  /// macOS/iOS 的 CFBundleShortVersionString 只接受纯数字，会把 `-0.2.0c` 这样的
  /// 预发布后缀截掉，故不能只靠 package_info——优先用此注入值，读不到再退回 package_info。
  static const String _definedVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '',
  );

  /// 启动时调用一次（main 里 runApp 之前）。
  static Future<void> init() async {
    try {
      _info = await PackageInfo.fromPlatform();
    } catch (_) {
      // 读不到（极少见）就退化，不影响启动。
    }
  }

  /// 版本名，如 `1.1.0-0.2.0c`。优先用构建注入值（保留预发布后缀），否则退回
  /// package_info（可能被平台截断成 `1.1.0`）。
  static String get version =>
      _definedVersion.isNotEmpty ? _definedVersion : (_info?.version ?? '');

  /// 展示用：版本名 + 构建号（提交），如 `1.1.0-0.2.0c (a1b2c3d)`；
  /// 未注入提交时仅版本名。
  static String get displayVersion {
    final v = version;
    if (commit.isEmpty) return v;
    return v.isEmpty ? commit : '$v ($commit)';
  }
}
