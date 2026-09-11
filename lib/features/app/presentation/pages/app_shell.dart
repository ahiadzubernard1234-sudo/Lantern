import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lantern/features/profile/presentation/providers/profile_provider.dart';
import 'package:lantern/features/app/presentation/pages/onboarding/profile_creation_screen.dart';
import 'package:lantern/features/app/presentation/pages/home/home_screen.dart';
import 'package:lantern/core/network/v2/network_coordinator.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({Key? key}) : super(key: key);

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _networkStarted = false;

  Future<void> _startNetworkIfNeeded(profile) async {
    if (_networkStarted || !mounted) return;
    _networkStarted = true;
    try {
      await NetworkServiceCoordinator().initialize(
        deviceId: profile.deviceId,
        username: profile.username,
        deviceName: profile.deviceName,
      );
    } catch (_) {
      _networkStarted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileNotifierProvider);

    return profileState.when(
      data: (profile) {
        if (profile == null) {
          return const ProfileCreationScreen();
        }
        _startNetworkIfNeeded(profile);
        return const HomeScreen();
      },
      loading: () => const _LoadingScreen(),
      error: (error, stackTrace) => const ProfileCreationScreen(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'LANtern',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ],
        ),
      ),
    );
  }
}
