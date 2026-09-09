import 'dart:convert';
import 'dart:typed_data';

import 'package:art3m1s/services/caption_table_probe.dart';
import 'package:art3m1s/services/project_charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jis0208/jis0208.dart';

void main() {
  test('prefers Japanese language table and ignores gametitle_trial', () {
    final files = <String, Uint8List>{
      'system/table/list_windows.tbl': Uint8List.fromList(
        utf8.encode('init={ gametitle_trial="Trial" }'),
      ),
      'system/table/list_windows_cn.tbl': Uint8List.fromList(
        utf8.encode('system={ gametitle="译名" }'),
      ),
      'system/table/list_windows_ja.tbl': Uint8List.fromList(
        utf8.encode('system={ gametitle = "サクラノ刻" }'),
      ),
    };

    expect(
      CaptionTableProbe.find(
        paths: files.keys,
        readFile: (path) => files[path],
        charset: 'UTF-8',
      ),
      'サクラノ刻',
    );
  });

  test('decodes Shift_JIS title according to system.ini', () {
    final ini = Uint8List.fromList(
      ascii.encode('[WINDOWS]\r\nCHARSET=Shift_JIS\r\n'),
    );
    final table = Windows31JEncoder().convert('gametitle="サクラノ刻"\r\n');

    expect(ProjectCharset.detect(ini, 'WINDOWS'), 'Shift_JIS');
    expect(
      CaptionTableProbe.find(
        paths: const ['system/table/list_windows_ja.tbl'],
        readFile: (_) => table,
        charset: ProjectCharset.detect(ini, 'WINDOWS'),
      ),
      'サクラノ刻',
    );
  });

  test('returns null when tables do not define gametitle', () {
    final table = Uint8List.fromList(
      utf8.encode('titlebgm="opening"\ngametitle_trial="Trial"'),
    );

    expect(
      CaptionTableProbe.find(
        paths: const ['system/table/list_windows.tbl'],
        readFile: (_) => table,
        charset: 'UTF-8',
      ),
      isNull,
    );
  });

  test('reads lua init tables that assign game_title', () {
    final files = <String, Uint8List>{
      'system/csv_ps4.tbl': Uint8List.fromList(
        utf8.encode('init = {\n\t["game_title"] = "千の刃濤、桃花染の皇姫",\n}\n'),
      ),
    };

    expect(
      CaptionTableProbe.find(
        paths: files.keys,
        readFile: (path) => files[path],
        charset: 'UTF-8',
      ),
      '千の刃濤、桃花染の皇姫',
    );
  });
}
