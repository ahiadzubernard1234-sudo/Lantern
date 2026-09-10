import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lantern/core/network/v2/providers/network_providers.dart';

class PeersTab extends ConsumerStatefulWidget {
  const PeersTab({Key? key}) : super(key: key);

  @override
  ConsumerState<PeersTab> createState() => _PeersTabState();
}

class _PeersTabState extends ConsumerState<PeersTab> {
  @override
  void initState() {
    super.initState();
    // Start peer discovery
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.radio_button_on, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Discovering peers...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Scanning your local network',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
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
                  trailing: Icon(peer.isOnline ? Icons.circle : Icons.circle_outlined, size: 12),
                ),
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}
