/// Android 宿主界面主题。其它平台忽略该设置。
enum HostUiTheme {
  material,
  miuix;

  String get label => switch (this) {
    HostUiTheme.material => 'Material Design',
    HostUiTheme.miuix => 'Miuix',
  };

  static HostUiTheme byName(String? name) {
    return HostUiTheme.values
            .where((value) => value.name == name)
            .firstOrNull ??
        HostUiTheme.material;
  }
}
