import 'dart:async';
import 'package:flutter/material.dart';
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
                child: Text('No users discovered yet', style: TextStyle(color: Colors.grey.shade600)),
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
            'Check that Wi-Fi is really connected, and turn off battery saver.',
      );
    }
    if (stats.received == 0) {
      return const _Diagnosis(
        _Health.warn,
        'Looking for people...',
        'Open LANtern on another phone that is on the same Wi-Fi or hotspot. '
            'If it still finds nobody, the router may block devices from seeing each other (client isolation). A phone hotspot always works.',
      );
    }
    return const _Diagnosis(
      _Health.warn,
      'Nobody is online right now',
      'Others were seen earlier but have gone quiet.',
    );
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
        if (c.isInitialized) {
          final m = c.networkMonitor;
          final s = c.discoveryService.stats;
          String yn(bool? v) => v == null ? 'unknown' : (v ? 'on' : 'off');
          lines.add('Wi-Fi radio: ${yn(m.wifiRadioOn)}');
          lines.add('Network: ${m.lanInterface ?? 'none'} ${m.getLocalIp() ?? ''}'.trim());
          lines.add('Broadcast: ${m.getBroadcastAddress() ?? 'none'}');
          lines.add('Packets sent ${s.sent}, heard ${s.received}, own ${s.ownReceived}');
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      ),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('View logs'),
                    ),
                    if (!c.isInitialized && c.lastInitError != null) ...[
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => unawaited(c.retryInitialize()),
                        child: const Text('Retry'),
                      ),
                    ],
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
