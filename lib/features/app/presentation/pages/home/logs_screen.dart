import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lantern/core/logging/app_log.dart';
import 'package:lantern/core/network/v2/network_coordinator.dart';

/// Shows what the app is doing right now, with a copy button for sharing.
class LogsScreen extends StatefulWidget {
  const LogsScreen({Key? key}) : super(key: key);

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

enum _LogFilter { info, problems, all }

class _LogsScreenState extends State<LogsScreen> {
  _LogFilter _filter = _LogFilter.info;
  String _query = '';

  bool _show(LogLine line) {
    if (_query.isNotEmpty && !line.message.toLowerCase().contains(_query)) {
      return false;
    }
    switch (_filter) {
      case _LogFilter.all:
        return true;
      case _LogFilter.problems:
        return line.level == 'warning' || line.level == 'error' || line.level == 'fatal';
      case _LogFilter.info:
        return line.level != 'debug' && line.level != 'trace' && line.level != 'verbose';
    }
  }

  Color? _color(String level) {
    switch (level) {
      case 'error':
      case 'fatal':
        return Colors.red;
      case 'warning':
        return Colors.orange.shade800;
      case 'debug':
      case 'trace':
      case 'verbose':
        return Colors.grey;
      default:
        return null;
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: AppLog.asText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
  }

  /// One-line summary of the live state, updated every second.
  String _liveSummary() {
    final c = NetworkServiceCoordinator();
    if (!c.isInitialized) {
      return c.lastInitError == null
          ? 'Network is starting...'
          : 'Network failed to start: ${c.lastInitError}';
    }
    final m = c.networkMonitor;
    final s = c.discoveryService.stats;
    final network = m.getLocalIp() == null
        ? m.statusMessage
        : '${m.lanInterface ?? 'network'} ${m.getLocalIp()}';
    return '$network\n'
        'Peers online ${c.discoveryService.onlinePeerCount}, '
        'secure sessions ${c.connectionManager.connectionCount}\n'
        'Broadcasts sent ${s.sent}, heard others ${s.received}, heard self ${s.ownReceived}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: AppLog.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // Live state
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: StreamBuilder<int>(
              stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
              builder: (context, _) => Text(
                _liveSummary(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<_LogFilter>(
              segments: const [
                ButtonSegment(value: _LogFilter.info, label: Text('Info')),
                ButtonSegment(value: _LogFilter.problems, label: Text('Problems')),
                ButtonSegment(value: _LogFilter.all, label: Text('All')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter, for example peer or handshake',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: AppLog.changes,
              builder: (context, _, __) {
                final lines = AppLog.lines.where(_show).toList().reversed.toList();
                if (lines.isEmpty) {
                  return const Center(child: Text('Nothing logged yet'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(
                        line.format(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: _color(line.level),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
