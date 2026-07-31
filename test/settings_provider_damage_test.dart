import 'package:art3m1s/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('脏区着色只能在调试模式中开启', () async {
    SharedPreferences.setMockInitialValues({
      'debug_mode': false,
      'damage_visualization': true,
    });
    final notifier = SettingsNotifier();
    await notifier.ready;

    expect(notifier.state.debugMode, isFalse);
    expect(notifier.state.damageVisualization, isFalse);

    await notifier.setDamageVisualization(true);
    expect(notifier.state.damageVisualization, isFalse);

    await notifier.setDebugMode(true);
    await notifier.setDamageVisualization(true);
    expect(notifier.state.damageVisualization, isTrue);

    await notifier.setDebugMode(false);
    expect(notifier.state.damageVisualization, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool('damage_visualization'),
      isFalse,
    );
    notifier.dispose();
  });
}
