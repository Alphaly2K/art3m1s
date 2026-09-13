import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../adaptive/ps5_chrome.dart';
import '../services/app_data_paths.dart';
import '../services/logger.dart';
import '../widgets/ps5_file_picker.dart';

/// 弹出字体选择器并把选中的字体字节导入沙箱托管目录，返回托管路径；
/// 取消或失败返回 null。
///
/// core 侧按单文件 sfnt 解析（TTF/OTF），不支持 TTC 合集，故类型组只放
/// ttf/otf。iOS 上选择器路径是安全作用域临时授权，按字节落盘而不是按路径
/// 复制（见 [AppDataPaths.importFontBytes]）。
Future<String?> pickOverrideFont([BuildContext? context]) async {
  String? path;
  String? name;
  if (context != null && usesPs5Chrome(context)) {
    path = await showPs5FilePicker(
      context,
      mode: Ps5FilePickerMode.file,
      title: '选择覆盖字体',
      allowedExtensions: const {'ttf', 'otf'},
    );
    if (path == null) return null;
    name = overrideFontDisplayName(path);
  } else {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: '字体', extensions: ['ttf', 'otf']),
      ],
      confirmButtonText: '选择',
    );
    if (file == null) return null;
    path = file.path;
    name = file.name;
  }
  try {
    final bytes = await File(path).readAsBytes();
    return await AppDataPaths.importFontBytes(name, bytes);
  } catch (error) {
    Log.warn('[字体] 覆盖字体导入失败: $name: $error');
    return null;
  }
}

/// 覆盖字体路径的显示名（跨平台分隔符）。
String overrideFontDisplayName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
