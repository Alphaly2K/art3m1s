import 'package:flutter/cupertino.dart';

/// iOS 分组列表：保留 `insetGrouped` 卡片外观，行间分割线改为双侧等距。
///
/// 原生 `CupertinoListSection` 的 shortDivider 只有起始边 inset，
/// 所以这里关掉原生分割线颜色，改在每一行底部叠加左右等距的 1px 线。
class CupertinoSymmetricListSection extends StatelessWidget {
  const CupertinoSymmetricListSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
  });

  static const double dividerInset = 16;

  final List<Widget> children;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: header,
      footer: footer,
      dividerMargin: 0,
      additionalDividerMargin: 0,
      hasLeading: false,
      separatorColor: const Color(0x00000000),
      children: [
        for (var i = 0; i < children.length; i++)
          _CupertinoSymmetricListRow(
            showDivider: i != children.length - 1,
            child: children[i],
          ),
      ],
    );
  }
}

class _CupertinoSymmetricListRow extends StatelessWidget {
  const _CupertinoSymmetricListRow({
    required this.child,
    required this.showDivider,
  });

  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    if (!showDivider) {
      return child;
    }

    return Stack(
      children: [
        child,
        const Positioned(
          left: CupertinoSymmetricListSection.dividerInset,
          right: CupertinoSymmetricListSection.dividerInset,
          bottom: 0,
          child: IgnorePointer(child: CupertinoSymmetricDivider()),
        ),
      ],
    );
  }
}

class CupertinoSymmetricDivider extends StatelessWidget {
  const CupertinoSymmetricDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1 / MediaQuery.devicePixelRatioOf(context),
      width: double.infinity,
      child: ColoredBox(color: CupertinoColors.separator.resolveFrom(context)),
    );
  }
}
