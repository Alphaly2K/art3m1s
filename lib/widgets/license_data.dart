import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一个包的全部许可证（一包可能有多条）。
class PackageLicenses {
  final String package;
  final List<List<LicenseParagraph>> licenses;

  const PackageLicenses({required this.package, required this.licenses});
}

const rustCoreLicenseAsset = 'assets/licenses/rust_third_party.json';

/// 从 [LicenseRegistry] 收集全部许可证并按包名排序。
///
/// Material 的 LicensePage 也是从同一注册表读取；这里自取数据以便
/// 在 macOS / Cupertino 壳里用原生风格渲染。
///
/// 额外并入 art3m1s-core 的 Cargo 依赖，避免关于页只列出 Dart/Flutter 包。
Future<List<PackageLicenses>> collectLicenses() async {
  final byPackage = <String, List<List<LicenseParagraph>>>{};
  await for (final entry in LicenseRegistry.licenses) {
    final paragraphs = entry.paragraphs.toList(growable: false);
    for (final package in entry.packages) {
      byPackage.putIfAbsent(package, () => []).add(paragraphs);
    }
  }
  for (final extra in await loadRustCoreLicenses()) {
    byPackage.putIfAbsent(extra.package, () => []).addAll(extra.licenses);
  }
  final result =
      byPackage.entries
          .map((e) => PackageLicenses(package: e.key, licenses: e.value))
          .toList()
        ..sort(
          (a, b) => a.package.toLowerCase().compareTo(b.package.toLowerCase()),
        );
  return result;
}

Future<List<PackageLicenses>> loadRustCoreLicenses() async {
  final raw = await rootBundle.loadString(rustCoreLicenseAsset);
  return parseRustCoreLicenses(raw);
}

@visibleForTesting
List<PackageLicenses> parseRustCoreLicenses(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  final result = <PackageLicenses>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final name = item['package']?.toString() ?? '';
    if (name.isEmpty) continue;
    final version = item['version']?.toString() ?? '';
    final spdx = item['spdx']?.toString() ?? '';
    final text = (item['text']?.toString() ?? '').trim();
    final label = version.isEmpty ? '$name (Rust)' : '$name $version (Rust)';
    final body = StringBuffer();
    if (spdx.isNotEmpty && !text.contains('SPDX-License-Identifier:')) {
      body.writeln('SPDX-License-Identifier: $spdx');
      body.writeln();
    }
    body.write(
      text.isEmpty ? 'License text was not bundled with this crate.' : text,
    );
    result.add(
      PackageLicenses(
        package: label,
        licenses: [
          [LicenseParagraph(body.toString(), 0)],
        ],
      ),
    );
  }
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
