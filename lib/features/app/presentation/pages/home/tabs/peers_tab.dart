import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lantern/core/network/v2/network_coordinator.dart';
import 'package:lantern/core/network/v2/providers/network_providers.dart';
import 'package:lantern/features/app/presentation/pages/home/logs_screen.dart';
import 'package:lantern/features/chat/presentation/pages/chat_screen.dart';

class PeersTab extends ConsumerStatefulWidget {
  const PeersTab({Key? key}) : super(key: key);

  @override
  ConsumerState<PeersTab> createState() => _PeersTabState();
}

class _PeersTabState extends ConsumerState<PeersTab> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _NetworkStatusCard(),
        const SizedBox(height: 16),
        Text(
          'Online Users',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ref.watch(discoveredPeersProvider).when(
          loading: () => const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          )),
          error: (error, _) => Center(child: Text('Discovery error: $error')),
          data: (peers) {
            if (peers.isEmpty) {
              return Center(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'No users found yet.\nTry "Add by address" above.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ));
            }
            return Column(
              children: peers.map((peer) => Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(peer.username.isEmpty ? '?' : peer.username[0].toUpperCase())),
                  title: Text(peer.username),
                  subtitle: Text('${peer.deviceName} • ${peer.ipAddress}:${peer.port}'),
                  trailing: Icon(
                    peer.isOnline ? Icons.circle : Icons.circle_outlined,
                    size: 12,
                    color: peer.isOnline ? Colors.green : Colors.grey,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
                  ),
                ),
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}

enum _Health { ok, warn, bad }

class _Diagnosis {
  final _Health health;
  final String title;
  final String detail;
  const _Diagnosis(this.health, this.title, this.detail);
}

/// Live status: is the network up, is discovery running, and what is wrong.
class _NetworkStatusCard extends StatelessWidget {
  const _NetworkStatusCard();

  _Diagnosis _diagnose(NetworkServiceCoordinator c) {
    if (!c.isInitialized) {
      if (c.lastInitError != null) {
        return _Diagnosis(_Health.bad, 'Network failed to start', c.lastInitError!);
      }
      return const _Diagnosis(
        _Health.warn,
        'Starting network...',
        'Setting up discovery and secure connections.',
      );
    }

    final monitor = c.networkMonitor;
    if (monitor.getLocalIp() == null) {
      return _Diagnosis(
        _Health.bad,
        monitor.wifiRadioOn == false ? 'Wi-Fi is off' : 'Not on a local network',
        monitor.statusMessage,
      );
    }

    final stats = c.discoveryService.stats;
    final online = c.discoveryService.onlinePeerCount;

    if (online > 0) {
      return _Diagnosis(
        _Health.ok,
        '$online ${online == 1 ? 'person' : 'people'} nearby',
        'Tap a name below to chat.',
      );
    }
    if (stats.sent >= 3 && stats.ownReceived == 0 && stats.received == 0) {
      return const _Diagnosis(
        _Health.bad,
        'Not receiving broadcasts',
        'This phone is not hearing anything on the network, not even itself. '
            'You can still connect with "Add by address". Also turn off battery saver.',
      );
    }
    if (stats.received == 0) {
      return const _Diagnosis(
        _Health.warn,
        'Looking for people...',
        'Open LANtern on another phone on the same Wi-Fi or hotspot. '
            'If nobody shows up, use "Add by address" with that phone\'s IP.',
      );
    }
    return const _Diagnosis(
      _Health.warn,
      'Nobody is online right now',
      'Others were seen earlier but have gone quiet.',
    );
  }

  Future<void> _addByAddress(BuildContext context) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _AddByAddressDialog(),
    );
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final c = NetworkServiceCoordinator();
        final diag = _diagnose(c);

        final color = diag.health == _Health.ok
            ? Colors.green
            : (diag.health == _Health.warn ? Colors.orange.shade800 : Colors.red);
        final icon = diag.health == _Health.ok
            ? Icons.check_circle
            : (diag.health == _Health.warn ? Icons.hourglass_top : Icons.error);

        final lines = <String>[];
        String? ownAddress;
        if (c.isInitialized) {
          final m = c.networkMonitor;
          final s = c.discoveryService.stats;
          String yn(bool? v) => v == null ? 'unknown' : (v ? 'on' : 'off');
          lines.add('Wi-Fi radio: ${yn(m.wifiRadioOn)}');
          lines.add('Network: ${m.lanInterface ?? 'none'} ${m.getLocalIp() ?? ''}'.trim());
          lines.add('Broadcast: ${m.getBroadcastAddress() ?? 'none'}');
          lines.add('Packets sent ${s.sent}, heard ${s.received}, own ${s.ownReceived}');
          ownAddress = c.ownAddress;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        diag.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(diag.detail, style: Theme.of(context).textTheme.bodySmall),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final line in lines)
                    Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
                if (ownAddress != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'My address: $ownAddress',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy my address',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: ownAddress!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Address copied')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: c.isInitialized ? () => _addByAddress(context) : null,
                      icon: const Icon(Icons.add_link),
                      label: const Text('Add by address'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      ),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('View logs'),
                    ),
                    if (!c.isInitialized && c.lastInitError != null)
                      FilledButton(
                        onPressed: () => unawaited(c.retryInitialize()),
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dialog for connecting to another phone by its IP address.
class _AddByAddressDialog extends StatefulWidget {
  const _AddByAddressDialog();

  @override
  State<_AddByAddressDialog> createState() => _AddByAddressDialogState();
}

class _AddByAddressDialogState extends State<_AddByAddressDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    NetworkServiceCoordinator().lastManualAddress().then((value) {
      if (value != null && mounted && _controller.text.isEmpty) {
        _controller.text = value;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await NetworkServiceCoordinator().connectManually(_controller.text);
    if (!mounted) return;
    if (result.ok) {
      Navigator.pop(context, result.message);
    } else {
      setState(() {
        _busy = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final own = NetworkServiceCoordinator().ownAddress;

    return AlertDialog(
      title: const Text('Add by address'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'On the other phone, open LANtern and read "My address" on the Peers tab. '
              'Type it here. If one phone runs a hotspot, that phone is usually 192.168.43.1.',
            ),
            if (own != null) ...[
              const SizedBox(height: 8),
              Text(
                'This phone: $own',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'IP address',
                hintText: '192.168.43.1',
                helperText: 'Port 15555 is used if you leave it out',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _connect(),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              const Text('Connecting...'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
