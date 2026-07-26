import 'package:flutter/widgets.dart';

/// 上下内缩的滚动条：替换桌面端默认贴边滚动条，
/// 避免 thumb 两端被窗口圆角截断。
class InsetScrollbar extends StatelessWidget {
  final ScrollController? controller;
  final Widget child;

  const InsetScrollbar({super.key, this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return ScrollConfiguration(
      // 关掉 ScrollBehavior 自动加的贴边滚动条，用下面这条内缩的。
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        controller: controller,
        thumbVisibility: false,
        thickness: 6,
        radius: const Radius.circular(3),
        // 上下留出窗口圆角的空间。
        mainAxisMargin: 14,
        crossAxisMargin: 3,
        thumbColor: dark ? const Color(0x66FFFFFF) : const Color(0x59000000),
        child: child,
      ),
    );
  }
}
