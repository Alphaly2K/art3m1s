import 'dart:convert';
import 'dart:typed_data';

/// Optional per-project compatibility overrides for storefront/runtime checks.
///
/// This layer is deliberately narrow: it only neutralizes known native
/// environment bootstrap scripts. Missing game assets remain missing.
class EnvironmentPatch {
  static final Map<String, Uint8List> _virtualFiles = {
    'system/dmm.lua': _script('-- Art3m1s environment compatibility patch\n'),
    'system/dmm.lub': _script('-- Art3m1s environment compatibility patch\n'),
    'system/dmmck.lua': _script('''
-- Art3m1s environment compatibility patch
function init_dmmck() end
'''),
    'system/extend/auth.lua': _script('''
-- Art3m1s environment compatibility patch
function authentication() end
'''),
    'system/extend/auth/dmmck.lua': _script('''
-- Art3m1s environment compatibility patch
function init_dmmck() end
function dmmck_login() end
function dmmck_logincheck() end
'''),
  };

  static String normalizePath(String path) {
    final parts = <String>[];
    for (final raw in path.replaceAll('\\', '/').split('/')) {
      if (raw.isEmpty || raw == '.') continue;
      if (raw == '..') return '';
      parts.add(raw);
    }
    return parts.join('/').toLowerCase();
  }

  static Uint8List? virtualFile(String path) {
    final bytes = _virtualFiles[normalizePath(path)];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  static bool canTransform(String path) =>
      normalizePath(path) == 'system/first.iet';

  /// Artemis scripts found in the affected titles use C-style block comments
  /// around startup verification tags, but those tags may still be parsed.
  /// Convert only block-comment contents before the first Lua section into
  /// native `//` script comments.
  static Uint8List transform(String path, Uint8List original) {
    if (!canTransform(path)) return original;

    final text = latin1.decode(original);
    final luaStart = text.indexOf('[lua]');
    final prefixEnd = luaStart < 0 ? text.length : luaStart;
    final prefix = text.substring(0, prefixEnd);
    final patchedPrefix = prefix.replaceAllMapped(RegExp(r'/\*([\s\S]*?)\*/'), (
      match,
    ) {
      final block = match.group(0)!;
      return block.splitMapJoin(
        RegExp(r'\r\n|\n|\r'),
        onMatch: (separator) => separator.group(0)!,
        onNonMatch: (line) {
          if (line.trim().isEmpty || line.trimLeft().startsWith('//')) {
            return line;
          }
          final indent = line.substring(
            0,
            line.length - line.trimLeft().length,
          );
          return '$indent// ${line.trimLeft()}';
        },
      );
    });
    if (patchedPrefix == prefix) return original;
    return Uint8List.fromList(
      latin1.encode('$patchedPrefix${text.substring(prefixEnd)}'),
    );
  }

  static Uint8List _script(String source) =>
      Uint8List.fromList(utf8.encode(source));
}
