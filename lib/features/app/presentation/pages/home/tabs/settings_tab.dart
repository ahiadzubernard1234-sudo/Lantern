import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lantern/core/network/v2/network_coordinator.dart';
import 'package:lantern/core/theme/app_theme.dart';
import 'package:lantern/features/profile/presentation/providers/profile_provider.dart';
import 'package:lantern/features/app/presentation/pages/home/logs_screen.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileNotifierProvider);
    final themeMode = ref.watch(themeModeProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Profile Section
        Text(
          'Profile',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        profileState.when(
          data: (profile) {
            if (profile == null) {
              return const Text('No profile');
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.username,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      profile.deviceName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (profile.ipAddress != null)
                      Text(
                        'IP: ${profile.ipAddress}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _showEditProfileDialog(context, ref, profile),
                        child: const Text('Edit Profile'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const CircularProgressIndicator(),
          error: (error, stackTrace) => Text('Error: $error'),
        ),
        const SizedBox(height: 32),

        // Security Section
        Text(
          'Security',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<int>(
              stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
              builder: (context, _) {
                final coordinator = NetworkServiceCoordinator();
                final fingerprint =
                    coordinator.isInitialized ? coordinator.localFingerprint : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_outlined),
                        const SizedBox(width: 8),
                        Text(
                          'Encrypted connections',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your identity fingerprint',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      fingerprint ?? 'Starting...',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Compare this with a friend in person to be sure you are '
                      'chatting with the right device.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Theme Section
        Text(
          'Appearance',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Dark Mode'),
                Switch(
                  value: themeMode == ThemeMode.dark,
                  onChanged: (value) {
                    ref.read(themeModeProvider.notifier).state =
                        value ? ThemeMode.dark : ThemeMode.light;
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Network Section
        Text(
          'Network',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Discovery Status'),
                    StreamBuilder<int>(
                      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
                      builder: (context, _) {
                        final active = NetworkServiceCoordinator().isInitialized;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: active ? Colors.green.shade100 : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            active ? 'Active' : 'Starting',
                            style: TextStyle(
                              color: active ? Colors.green : Colors.orange.shade800,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showNetworkDiagnostics(context),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Network Diagnostics'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LogsScreen()),
                    ),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('View Logs'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),

        // About Section
        Text(
          'About',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Version'),
                    Text('1.0.0', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Build'),
                    Text('1', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'A local-first social hub for LAN communication',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _showEditProfileDialog(BuildContext context, WidgetRef ref, dynamic profile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: const Text('Profile editing coming soon'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          const SizedBox(width: 16),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  String _yesNo(bool? value) => value == null ? 'unknown' : (value ? 'yes' : 'no');

  Future<void> _showNetworkDiagnostics(BuildContext context) async {
    final coordinator = NetworkServiceCoordinator();

    if (!coordinator.isInitialized) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Network Diagnostics'),
          content: Text(coordinator.lastInitError == null
              ? 'The network is still starting. Try again in a moment.'
              : 'The network failed to start:\n${coordinator.lastInitError}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    final diagnostics = coordinator.getDiagnostics();
    final queued = await coordinator.outboxService.pendingCount();
    final network = (diagnostics['network'] as Map?) ?? const {};
    final peers = (diagnostics['peers'] as Map?) ?? const {};
    final monitor = coordinator.networkMonitor;
    final stats = coordinator.discoveryService.stats;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Network Diagnostics'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Wi-Fi radio on', _yesNo(monitor.wifiRadioOn)),
              _row('Interface', monitor.lanInterface ?? 'none'),
              _row('Local IP', '${network['localIp'] ?? 'none'}'),
              _row('Subnet mask', '${network['subnetMask'] ?? 'unknown (using /24)'}'),
              _row('Broadcast', '${network['broadcastAddress'] ?? 'none'}'),
              _row('Multicast lock held', _yesNo(monitor.multicastLockHeld)),
              const Divider(),
              _row('Broadcasts sent', '${stats.sent}'),
              _row('Heard from others', '${stats.received}'),
              _row('Heard own broadcast', '${stats.ownReceived}'),
              _row('Last send error', stats.lastSendError ?? 'none'),
              const Divider(),
              _row('Peers discovered', '${peers['discovered'] ?? 0}'),
              _row('Peers online', '${peers['online'] ?? 0}'),
              _row('Secure sessions', '${peers['connected'] ?? 0}'),
              _row('Messages waiting', '$queued'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
