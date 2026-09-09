import 'package:art3m1s/models/render_output.dart';
import 'package:art3m1s/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('render output mode and custom extent persist', () async {
    SharedPreferences.setMockInitialValues({
      'render_output_mode': RenderOutputMode.custom.name,
      'custom_render_width': 3200,
      'custom_render_height': 1800,
    });
    final notifier = SettingsNotifier();
    await notifier.ready;

    expect(notifier.state.renderOutputMode, RenderOutputMode.custom);
    expect(notifier.state.customRenderWidth, 3200);
    expect(notifier.state.customRenderHeight, 1800);

    await notifier.setRenderOutputMode(RenderOutputMode.fixed2x);
    await notifier.setCustomRenderSize(3840, 2160);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('render_output_mode'),
      RenderOutputMode.fixed2x.name,
    );
    expect(preferences.getInt('custom_render_width'), 3840);
    expect(preferences.getInt('custom_render_height'), 2160);
    notifier.dispose();
  });

  test('legacy quality setting migrates to match-display output', () async {
    SharedPreferences.setMockInitialValues({'render_quality_preset': 3});
    final notifier = SettingsNotifier();
    await notifier.ready;
    expect(notifier.state.renderOutputMode, RenderOutputMode.matchDisplay);
    notifier.dispose();
  });
}
