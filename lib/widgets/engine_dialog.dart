import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine_runtime.dart';

Future<EngineDialogResult?> showEngineDialog(
  BuildContext context,
  EngineDialogRequest request,
) {
  return showDialog<EngineDialogResult>(
    context: context,
    barrierDismissible: request.hasCancel && request.choices.isEmpty,
    builder: (_) => PopScope(
      canPop: request.choices.isEmpty,
      child: _EngineDialog(request: request),
    ),
  );
}

class _EngineDialog extends StatefulWidget {
  const _EngineDialog({required this.request});

  final EngineDialogRequest request;

  @override
  State<_EngineDialog> createState() => _EngineDialogState();
}

class _EngineDialogState extends State<_EngineDialog> {
  late final TextEditingController _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.request.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close(bool accepted, {int? choice}) {
    if (_completed) return;
    _completed = true;
    final result = EngineDialogResult(
      accepted: accepted,
      text: _controller.text,
      choice: choice,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      title: request.title.isEmpty ? null : Text(request.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (request.message.isNotEmpty) Text(request.message),
          if (request.message.isNotEmpty && request.hasTextField)
            const SizedBox(height: 16),
          if (request.hasTextField)
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                if (request.textFieldSize case final limit?)
                  LengthLimitingTextInputFormatter(limit),
              ],
              onSubmitted: (_) => _close(true),
            ),
        ],
      ),
      actions: request.choices.isNotEmpty
          ? [
              for (final (index, choice) in request.choices.indexed)
                if (index == 0)
                  FilledButton(
                    onPressed: () => _close(true, choice: choice.value),
                    child: Text(choice.label),
                  )
                else
                  TextButton(
                    onPressed: () => _close(false, choice: choice.value),
                    child: Text(choice.label),
                  ),
            ]
          : [
              if (request.hasCancel)
                TextButton(
                  onPressed: () => _close(false),
                  child: Text(localizations.cancelButtonLabel),
                ),
              FilledButton(
                onPressed: () => _close(true),
                child: Text(localizations.okButtonLabel),
              ),
            ],
    );
  }
}
