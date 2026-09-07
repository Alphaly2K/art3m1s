import 'package:art3m1s/models/host_ui_theme.dart';
import 'package:art3m1s/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Android host UI theme persists', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SettingsNotifier();
    await notifier.ready;

    expect(notifier.state.hostUiTheme, HostUiTheme.material);

    await notifier.setHostUiTheme(HostUiTheme.miuix);
    expect(notifier.state.hostUiTheme, HostUiTheme.miuix);
    expect(
      (await SharedPreferences.getInstance()).getString('host_ui_theme'),
      'miuix',
    );

    notifier.dispose();

    final reloaded = SettingsNotifier();
    await reloaded.ready;
    expect(reloaded.state.hostUiTheme, HostUiTheme.miuix);
    reloaded.dispose();
  });

  test('unknown host UI theme falls back to Material', () {
    expect(HostUiTheme.byName(null), HostUiTheme.material);
    expect(HostUiTheme.byName('unknown'), HostUiTheme.material);
    expect(HostUiTheme.byName('miuix'), HostUiTheme.miuix);
  });
}
