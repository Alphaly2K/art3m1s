import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class Log {
  static final _logs = <LogEntry>[];
  static final _notifier = ValueNotifier<int>(0);
  static bool _debugEnabled = false;
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

  static void _add(String level, String msg) {
    _logs.add(LogEntry(DateTime.now(), level, msg));
    if (_logs.length > 5000) _logs.removeRange(0, _logs.length - 5000);
    _notifier.value = _logs.length;
    _writeFile(level, msg);
  }

  static void debug(String msg) {
    if (_debugEnabled) _add('D', msg);
  }

  static void info(String msg) => _add('I', msg);
  static void warn(String msg) => _add('W', msg);
  static void error(String msg) => _add('E', msg);

  static Future<File> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/art3m1s_${DateTime.now().millisecondsSinceEpoch}.log');
    final sink = file.openWrite();
    for (final e in _logs) {
      sink.writeln('[${e.timestamp.toIso8601String()}] [${e.level}] ${e.message}');
    }
    await sink.close();
    return file;
  }

  static void clear() {
    _logs.clear();
    _notifier.value = 0;
  }

  static Future<void> _writeFile(String level, String msg) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/art3m1s.log');
      await file.writeAsString(
        '[${DateTime.now().toIso8601String()}] [$level] $msg\n',
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
  const DebugOverlay({super.key});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  Offset _pos = const Offset(60, 200);
  Size _size = const Size(520, 300);
  static const _minSize = Size(300, 150);
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
      child: GestureDetector(
        onPanUpdate: _move,
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xEE1A1A2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xCC000000),
        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          const Text('调试', style: TextStyle(fontSize: 11, color: Colors.white54)),
          const Spacer(),
          Text('$count', style: const TextStyle(fontSize: 10, color: Colors.white30)),
          const SizedBox(width: 8),
          _btn(Icons.pause, _autoScroll, () => setState(() => _autoScroll = !_autoScroll)),
          _btn(Icons.copy, false, () async {
            final text = entries.map((e) => '[${e.timestamp}] [${e.level}] ${e.message}').join('\n');
            await Clipboard.setData(ClipboardData(text: text));
          }),
          _btn(Icons.delete_outline, false, Log.clear),
          _btn(Icons.close, false, () => _close()),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: 14, color: active ? Colors.greenAccent : Colors.white54),
    );
  }

  Widget _buildLogList(List<LogEntry> entries) {
    if (entries.isEmpty) {
      return const Center(child: Text('等待日志...', style: TextStyle(color: Colors.white30, fontSize: 12)));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 0.5),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${_ts(e.timestamp)} ',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              TextSpan(text: '[${e.level}] ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _lc(e.level))),
              TextSpan(text: e.message, style: const TextStyle(fontSize: 11)),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildResizeHandle() {
    return GestureDetector(
      onPanUpdate: _resize,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Container(
          width: 16, height: 16,
          decoration: const BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: const Icon(Icons.drag_indicator, size: 10, color: Colors.white30),
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
    Log.setOverlay(false);
  }

  String _ts(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';

  Color _lc(String l) => switch (l) {
        'D' => Colors.cyan, 'I' => Colors.green, 'W' => Colors.orange, 'E' => Colors.red, _ => Colors.white,
      };
}
