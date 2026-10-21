import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// One line in the in-app log.
class LogLine {
  final DateTime time;
  final String level;
  final String message;

  const LogLine(this.time, this.level, this.message);

  String format() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    return '$t ${level.toUpperCase().padRight(7)} $message';
  }
}

/// In-memory log that the app can show on screen and copy out.
///
/// Every `Logger` in the app feeds into it once [install] has been called.
class AppLog {
  static const int maxLines = 1500;

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static final List<LogLine> _lines = [];
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;
    Logger.addLogListener((LogEvent event) {
      final error = event.error != null ? ' | ${event.error}' : '';
      add(event.level.name, '${event.message}$error');
    });
    add('info', 'Log started');
  }

  static void add(String level, String message) {
    _lines.add(LogLine(DateTime.now(), level, message));
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    Future.microtask(() => changes.value++);
  }

  static List<LogLine> get lines => List.unmodifiable(_lines);

  static void clear() {
    _lines.clear();
    Future.microtask(() => changes.value++);
  }

  static String asText() => _lines.map((l) => l.format()).join('\n');
}
