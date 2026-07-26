import 'package:flutter/foundation.dart';

/// 一个包的全部许可证（一包可能有多条）。
class PackageLicenses {
  final String package;
  final List<List<LicenseParagraph>> licenses;

  const PackageLicenses({required this.package, required this.licenses});
}

/// 从 [LicenseRegistry] 收集全部许可证并按包名排序。
///
/// Material 的 LicensePage 也是从同一注册表读取；这里自取数据以便
/// 在 macOS / Cupertino 壳里用原生风格渲染。
Future<List<PackageLicenses>> collectLicenses() async {
  final byPackage = <String, List<List<LicenseParagraph>>>{};
  await for (final entry in LicenseRegistry.licenses) {
    final paragraphs = entry.paragraphs.toList(growable: false);
    for (final package in entry.packages) {
      byPackage.putIfAbsent(package, () => []).add(paragraphs);
    }
  }
  final result = byPackage.entries
      .map((e) => PackageLicenses(package: e.key, licenses: e.value))
      .toList()
    ..sort(
      (a, b) => a.package.toLowerCase().compareTo(b.package.toLowerCase()),
    );
  return result;
}

/// 把段落列表拼成显示文本（缩进段落前置空格，段间空行）。
String licenseText(List<LicenseParagraph> paragraphs) {
  final buffer = StringBuffer();
  for (final p in paragraphs) {
    if (buffer.isNotEmpty) buffer.write('\n\n');
    if (p.indent == LicenseParagraph.centeredIndent) {
      buffer.write(p.text);
    } else {
      buffer.write('${'    ' * p.indent}${p.text}');
    }
  }
  return buffer.toString();
}
