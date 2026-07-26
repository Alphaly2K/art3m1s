import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class Log {
  static final _logs = <LogEntry>[];
  static final _runtimeSessionLogs = <LogEntry>[];
  static final _notifier = ValueNotifier<int>(0);
  static Future<void> _fileWriteQueue = Future<void>.value();
  static bool _debugEnabled = false;
  static bool _runtimeSessionActive = false;
  static bool _hasRuntimeSession = false;
  static bool overlayVisible = false;
  static VoidCallback? _onOverlayToggle;

  static bool get debugEnabled => _debugEnabled;
  static void setDebugEnabled(bool v) => _debugEnabled = v;
  static ValueNotifier<int> get notifier => _notifier;
  static List<LogEntry> get entries => List.unmodifiable(_logs);

  static void setOverlay(bool v) {
    overlayVisible = v;
    _onOverlayToggle?.call();
  }

  static void bind(VoidCallback onToggle) {
    _onOverlayToggle = onToggle;
  }

  static void startRuntimeSession() {
    _runtimeSessionLogs.clear();
    _runtimeSessionActive = true;
    _hasRuntimeSession = true;
    _fileWriteQueue = _fileWriteQueue.then((_) => _truncateCurrentLog());
  }

  static void endRuntimeSession() {
    _runtimeSessionActive = false;
  }

  static void _add(String level, String msg) {
    final entry = LogEntry(DateTime.now(), level, msg);
    _logs.add(entry);
    if (_runtimeSessionActive) {
      _runtimeSessionLogs.add(entry);
    }
    if (_logs.length > 5000) _logs.removeRange(0, _logs.length - 5000);
    _notifier.value = _logs.length;
    _fileWriteQueue = _fileWriteQueue.then((_) => _writeFile(entry));
  }

  static void debug(String msg) {
    if (_debugEnabled) _add('D', msg);
  }

  static void info(String msg) => _add('I', msg);
  static void warn(String msg) => _add('W', msg);
  static void error(String msg) => _add('E', msg);

  static Future<File> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/art3m1s_${DateTime.now().millisecondsSinceEpoch}.log',
    );
    final sink = file.openWrite();
    final entries = _hasRuntimeSession ? _runtimeSessionLogs : _logs;
    for (final e in entries) {
      sink.writeln(
        '[${e.timestamp.toIso8601String()}] [${e.level}] ${e.message}',
      );
    }
    await sink.close();
    return file;
  }

  static void clear() {
    _logs.clear();
    _notifier.value = 0;
  }

  static Future<void> _truncateCurrentLog() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/art3m1s.log');
      await file.writeAsString('');
    } catch (_) {}
  }

  static Future<void> _writeFile(LogEntry entry) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/art3m1s.log');
      await file.writeAsString(
        '[${entry.timestamp.toIso8601String()}] [${entry.level}] ${entry.message}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }
}

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  const LogEntry(this.timestamp, this.level, this.message);
}

/// Draggable + resizable debug console overlay.
class DebugOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const DebugOverlay({super.key, required this.onClose});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  Offset _pos = const Offset(60, 200);
  Size _size = const Size(520, 300);
  static const _minSize = Size(300, 150);
  static String get _fontFamily {
    if (Platform.isMacOS || Platform.isIOS) return 'Menlo';
    if (Platform.isWindows) return 'Consolas';
    if (Platform.isLinux) return 'DejaVu Sans Mono';
    return 'monospace';
  }

  final _scroll = ScrollController();
  bool _autoScroll = true;
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    Log.notifier.addListener(_onLog);
  }

  @override
  void dispose() {
    Log.notifier.removeListener(_onLog);
    _scroll.dispose();
    super.dispose();
  }

  void _onLog() {
    _scheduleRefresh(scrollToBottom: _autoScroll);
  }

  void _scheduleRefresh({bool scrollToBottom = false}) {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!mounted) return;
      setState(() {});
      if (scrollToBottom && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = Log.entries;

    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      width: _size.width,
      height: _size.height,
      // 自成一体的深色控制台：显式浅色文字，不依赖环境主题（浮层在根 Overlay，
      // 拿不到 app 主题的文字色，之前正文因此在深色下不可见）。
      child: Material(
        color: Colors.transparent,
        elevation: 16,
        borderRadius: BorderRadius.circular(10),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: _fontFamily,
            fontSize: 11,
            height: 1.35,
            color: Color(0xFFD4D4D8),
            decoration: TextDecoration.none,
          ),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xF218181B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Column(
              children: [
                _buildHeader(entries.length, entries),
                Expanded(child: _buildLogList(entries)),
                _buildResizeHandle(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int count, List<LogEntry> entries) {
    // 顶栏兼作拖动把手（之前整块面板可拖，会和日志列表滚动抢手势）。
    return GestureDetector(
      onPanUpdate: _move,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        decoration: const BoxDecoration(
          color: Color(0xFF232329),
          border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
        ),
        child: Row(
          children: [
            const Icon(Icons.terminal, size: 13, color: Color(0xFF8B8B93)),
            const SizedBox(width: 6),
            const Text(
              '调试控制台',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE4E4E7),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0x1FFFFFFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)),
              ),
            ),
            const Spacer(),
            _btn(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
              _autoScroll ? '自动滚动（点击暂停）' : '已暂停（点击恢复）',
              _autoScroll,
              () => setState(() => _autoScroll = !_autoScroll),
            ),
            _btn(Icons.copy_all_outlined, '复制全部', false, () async {
              final text = entries
                  .map((e) => '[${e.timestamp}] [${e.level}] ${e.message}')
                  .join('\n');
              await Clipboard.setData(ClipboardData(text: text));
            }),
            _btn(Icons.delete_outline, '清空', false, Log.clear),
            _btn(Icons.close, '关闭', false, _close),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String tip, bool active, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Icon(
            icon,
            size: 15,
            color: active ? const Color(0xFF4ADE80) : const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }

  Widget _buildLogList(List<LogEntry> entries) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          '等待日志…',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
        ),
      );
    }
    return Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        itemCount: entries.length,
        itemBuilder: (_, i) {
          final e = entries[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${_ts(e.timestamp)}  ',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  TextSpan(
                    text: '${e.level}  ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _lc(e.level),
                    ),
                  ),
                  // 正文：显式浅色，深色控制台上清晰可读。
                  TextSpan(
                    text: e.message,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFD4D4D8),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResizeHandle() {
    return Align(
      alignment: Alignment.bottomRight,
      child: GestureDetector(
        onPanUpdate: _resize,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.all(3),
          child: Icon(Icons.south_east, size: 12, color: Color(0xFF6B7280)),
        ),
      ),
    );
  }

  void _move(DragUpdateDetails d) {
    setState(() => _pos += d.delta);
  }

  void _resize(DragUpdateDetails d) {
    setState(() {
      _size = Size(
        (_size.width + d.delta.dx).clamp(_minSize.width, 1200),
        (_size.height + d.delta.dy).clamp(_minSize.height, 900),
      );
    });
  }

  void _close() {
    widget.onClose();
  }

  String _ts(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';

  // 深色控制台上高对比的级别色。
  Color _lc(String l) => switch (l) {
    'D' => const Color(0xFF38BDF8), // sky
    'I' => const Color(0xFF4ADE80), // green
    'W' => const Color(0xFFFBBF24), // amber
    'E' => const Color(0xFFF87171), // red
    _ => const Color(0xFF9CA3AF),
  };
}
