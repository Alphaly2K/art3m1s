import 'dart:convert';
import 'dart:typed_data';

import 'package:jis0208/jis0208.dart';

class ProjectCharset {
  static String detect(Uint8List ini, String platform) {
    final section = platform.trim().toUpperCase();
    String? current;
    for (final rawLine in String.fromCharCodes(
      ini.map((byte) => byte < 0x80 ? byte : 0x20),
    ).split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        current = line.substring(1, line.length - 1).trim().toUpperCase();
        continue;
      }
      if (current != section) continue;
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim().toUpperCase();
      if (key == 'CHARSET') return normalize(line.substring(eq + 1));
    }
    return 'Shift_JIS';
  }

  static String normalize(String value) {
    return switch (value.trim().toUpperCase()) {
      'UTF-8' || 'UTF8' => 'UTF-8',
      'SHIFT_JIS' || 'SHIFT-JIS' || 'SJIS' || 'WINDOWS-31J' => 'Shift_JIS',
      _ => 'Shift_JIS',
    };
  }

  static String decode(Uint8List bytes, String charset) {
    final text = normalize(charset) == 'UTF-8'
        ? utf8.decode(bytes, allowMalformed: true)
        : Windows31JDecoder(allowMalformed: true).convert(bytes);
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }
}
