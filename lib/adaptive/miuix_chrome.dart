import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// Android 当前是否正在使用 Miuix 壳。其它平台恒为 false。
bool usesMiuixChrome(BuildContext context) {
  return Platform.isAndroid && MiuixTheme.maybeOf(context) != null;
}

Widget miuixNamedIcon(String name, {double? size}) {
  final vector = MiuixIcons.extended.byName(name);
  if (vector == null) {
    return Icon(Icons.circle_outlined, size: size);
  }
  return MiuixIcon(vector: vector, size: size);
}

Widget miuixBarAction({required VoidCallback onPressed, required String icon}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Center(
      child: MiuixIconButton(onPressed: onPressed, child: miuixNamedIcon(icon)),
    ),
  );
}

/// Miuix 卡片列表项之间的分割线。双侧保持相同内缩，避免一端贴住卡片边缘。
class MiuixInsetDivider extends StatelessWidget {
  const MiuixInsetDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: 16),
      child: MiuixHorizontalDivider(),
    );
  }
}

class MiuixSettingsGroup extends StatelessWidget {
  const MiuixSettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MiuixSmallTitle(title),
        MiuixCard(
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const MiuixInsetDivider(),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Future<T?> showMiuixHostedOverlay<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    bool show,
    void Function([T? result]) dismiss,
    VoidCallback finish,
  )
  overlay,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) {
        return _MiuixHostedOverlay<T>(overlay: overlay);
      },
    ),
  );
}

class _MiuixHostedOverlay<T> extends StatefulWidget {
  const _MiuixHostedOverlay({required this.overlay});

  final Widget Function(
    BuildContext context,
    bool show,
    void Function([T? result]) dismiss,
    VoidCallback finish,
  )
  overlay;

  @override
  State<_MiuixHostedOverlay<T>> createState() => _MiuixHostedOverlayState<T>();
}

class _MiuixHostedOverlayState<T> extends State<_MiuixHostedOverlay<T>> {
  bool _show = true;
  T? _result;
  var _finished = false;

  void _dismiss([T? result]) {
    if (!_show) return;
    setState(() {
      _result = result;
      _show = false;
    });
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: MiuixPopupScope(
        establishRoot: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const MiuixPopupHost(),
            widget.overlay(context, _show, _dismiss, _finish),
          ],
        ),
      ),
    );
  }
}

Future<bool> showMiuixConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  final result = await showMiuixHostedOverlay<bool>(
    context: context,
    overlay: (context, show, dismiss, finish) {
      final theme = MiuixTheme.of(context);
      final colors = destructive
          ? MiuixButtonColors(
              color: theme.colors.error,
              disabledColor: theme.colors.disabledPrimaryButton,
              contentColor: theme.colors.onError,
              disabledContentColor: theme.colors.disabledOnPrimaryButton,
            )
          : MiuixButtonDefaults.buttonColorsPrimary(context);
      return MiuixOverlayDialog(
        show: show,
        title: title,
        summary: message,
        renderInRootScaffold: false,
        onDismissRequest: () => dismiss(false),
        onDismissFinished: finish,
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MiuixTextButton('取消', onPressed: () => dismiss(false)),
              const SizedBox(width: 12),
              MiuixButton(
                colors: colors,
                onPressed: () => dismiss(true),
                child: MiuixText(confirmLabel, style: theme.textStyles.button),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

Future<T?> showMiuixSheet<T>({
  required BuildContext context,
  String? title,
  required Widget Function(
    BuildContext context,
    void Function([T? result]) dismiss,
  )
  content,
}) {
  return showMiuixHostedOverlay<T>(
    context: context,
    overlay: (context, show, dismiss, finish) {
      return MiuixOverlayBottomSheet(
        show: show,
        title: title,
        renderInRootScaffold: false,
        onDismissRequest: dismiss,
        onDismissFinished: finish,
        content: content(context, dismiss),
      );
    },
  );
}
