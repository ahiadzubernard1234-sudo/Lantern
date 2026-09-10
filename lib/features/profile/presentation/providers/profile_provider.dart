import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lantern/core/di/service_locator.dart';
import 'package:lantern/features/profile/domain/entities/profile.dart';
import 'package:lantern/features/profile/domain/repositories/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ServiceLocator().profileRepository;
});

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.getProfile();
});

final profileNotifierProvider = StateNotifierProvider<ProfileNotifier, AsyncValue<Profile?>>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(repository);
});

class ProfileNotifier extends StateNotifier<AsyncValue<Profile?>> {
  final ProfileRepository _repository;

  ProfileNotifier(this._repository) : super(const AsyncValue.loading()) {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.getProfile());
  }

  Future<void> createProfile({
    required String username,
    required String deviceName,
    required String deviceId,
    String? avatarPath,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.createProfile(
        username: username,
        deviceName: deviceName,
        deviceId: deviceId,
        avatarPath: avatarPath,
      );
      return _repository.getProfile();
    });
  }

  Future<void> updateProfile({
    String? username,
    String? avatarPath,
    String? deviceName,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repository.updateProfile(
        username: username,
        avatarPath: avatarPath,
        deviceName: deviceName,
      );
      return _repository.getProfile();
    });
  }

  Future<void> refreshProfile() async {
    await _loadProfile();
  }
}
