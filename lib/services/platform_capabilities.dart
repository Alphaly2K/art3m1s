import 'dart:io';

class PlatformCapabilities {
  PlatformCapabilities._();

  static bool get supportsLiquidGlass {
    if (!Platform.isIOS) return false;
    final match = RegExp(r'\d+').firstMatch(Platform.operatingSystemVersion);
    final major = match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
    return major >= 26;
  }
}
