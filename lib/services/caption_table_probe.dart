import 'dart:typed_data';

import 'project_charset.dart';

class CaptionTableProbe {
  static final RegExp _gameTitle = RegExp(
    r'''\bgametitle\s*=\s*(?:"([^"\r\n]*)"|'([^'\r\n]*)')''',
    caseSensitive: false,
  );

  static String? find({
    required Iterable<String> paths,
    required Uint8List? Function(String path) readFile,
    required String charset,
  }) {
    final candidates =
        paths
            .where((path) => path.toLowerCase().endsWith('.tbl'))
            .where((path) => !_basename(path).startsWith('._'))
            .toList()
          ..sort(_comparePaths);

    for (final path in candidates) {
      final bytes = readFile(path);
      if (bytes == null || bytes.isEmpty) continue;
      final source = ProjectCharset.decode(bytes, charset);
      for (final line in source.split(RegExp(r'[\r\n]+'))) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('--') ||
            trimmed.startsWith('//') ||
            trimmed.startsWith('#')) {
          continue;
        }
        final match = _gameTitle.firstMatch(line);
        final title = match?.group(1) ?? match?.group(2);
        if (title != null && title.trim().isNotEmpty) {
          return _unescape(title.trim());
        }
      }
    }
    return null;
  }

  static int _comparePaths(String left, String right) {
    final rank = _rank(left).compareTo(_rank(right));
    return rank != 0 ? rank : left.compareTo(right);
  }

  static int _rank(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final basename = _basename(normalized);
    var rank = normalized.startsWith('system/table/') ? 0 : 100;
    if (RegExp(r'^list_.+_ja\.tbl$').hasMatch(basename)) {
      rank += 0;
    } else if (RegExp(r'^list_.+\.tbl$').hasMatch(basename)) {
      rank += 10;
    } else if (basename.endsWith('_ja.tbl')) {
      rank += 20;
    } else {
      rank += 30;
    }
    return rank;
  }

  static String _basename(String path) =>
      path.replaceAll('\\', '/').split('/').last.toLowerCase();

  static String _unescape(String value) => value
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'")
      .replaceAll(r'\\', r'\');
}
