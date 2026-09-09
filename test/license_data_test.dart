import 'package:art3m1s/widgets/license_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseRustCoreLicenses labels crate versions', () {
    const raw =
        '[{"package":"ab_glyph","version":"0.2.32","spdx":"Apache-2.0","text":"Apache text"}]';
    final parsed = parseRustCoreLicenses(raw);
    expect(parsed, hasLength(1));
    expect(parsed.single.package, 'ab_glyph 0.2.32 (Rust)');
    expect(
      licenseText(parsed.single.licenses.single),
      contains('SPDX-License-Identifier: Apache-2.0'),
    );
    expect(licenseText(parsed.single.licenses.single), contains('Apache text'));
  });

  test('bundled rust licenses include art3m1s-core dependencies', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final licenses = await loadRustCoreLicenses();
    final names = licenses.map((item) => item.package).toList();
    expect(names, anyElement(contains('art3m1s-core')));
    expect(names, anyElement(contains('ab_glyph')));
    expect(names, anyElement(contains('mlua')));
  });

  test('bundled rust licenses keep crate licenses accurate', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final licenses = await loadRustCoreLicenses();
    String textOf(String needle) {
      return licenseText(
        licenses
            .firstWhere((item) => item.package.contains(needle))
            .licenses
            .single,
      );
    }

    final decrypt = textOf('asb-decrypt');
    expect(decrypt, contains('BSD-3-Clause'));
    expect(
      decrypt,
      contains('Redistribution and use in source and binary forms'),
    );
    expect(decrypt, isNot(contains('GNU AFFERO')));

    final interpreter = textOf('asb-interpreter');
    expect(interpreter, contains('MPL-2.0'));
    expect(interpreter, contains('Mozilla Public License'));
    expect(interpreter, isNot(contains('GNU AFFERO')));

    final core = textOf('art3m1s-core');
    expect(core, contains('MPL-2.0'));
    expect(core, contains('Mozilla Public License'));
  });
}
