import 'package:flutter/cupertino.dart';

/// iOS 分组列表：保留 `insetGrouped` 卡片外观，但把行间分割线改为双侧等距。
class CupertinoSymmetricListSection extends StatelessWidget {
  const CupertinoSymmetricListSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
  });

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
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0) const CupertinoSymmetricDivider(),
              children[i],
            ],
          ),
      ],
    );
  }
}

class CupertinoSymmetricDivider extends StatelessWidget {
  const CupertinoSymmetricDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      child: SizedBox(
        height: 1 / MediaQuery.devicePixelRatioOf(context),
        child: ColoredBox(
          color: CupertinoColors.separator.resolveFrom(context),
        ),
      ),
    );
  }
}
