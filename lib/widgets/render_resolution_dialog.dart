import 'package:flutter/material.dart';

Future<({int width, int height})?> showRenderResolutionDialog(
  BuildContext context, {
  required int width,
  required int height,
}) async {
  final widthController = TextEditingController(text: width.toString());
  final heightController = TextEditingController(text: height.toString());
  String? error;
  try {
    return await showDialog<({int width, int height})>(
      context: context,
      builder: (dialogContext) => Theme(
        data: ThemeData(brightness: MediaQuery.platformBrightnessOf(context)),
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('自定义输出分辨率'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widthController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '宽度'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('×'),
                      ),
                      Expanded(
                        child: TextField(
                          controller: heightController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '高度'),
                        ),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final parsedWidth = int.tryParse(widthController.text.trim());
                  final parsedHeight = int.tryParse(
                    heightController.text.trim(),
                  );
                  if (parsedWidth == null ||
                      parsedHeight == null ||
                      parsedWidth <= 0 ||
                      parsedHeight <= 0 ||
                      parsedWidth > 16384 ||
                      parsedHeight > 16384) {
                    setDialogState(() => error = '请输入 1–16384 范围内的宽度和高度');
                    return;
                  }
                  Navigator.pop(dialogContext, (
                    width: parsedWidth,
                    height: parsedHeight,
                  ));
                },
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    widthController.dispose();
    heightController.dispose();
  }
}
