import 'package:lantern/features/profile/domain/entities/profile.dart';

abstract class ProfileRepository {
  Future<void> createProfile({
    required String username,
    required String deviceName,
    required String deviceId,
    String? avatarPath,
  });

  Future<Profile?> getProfile();

  Future<void> updateProfile({
    String? username,
    String? avatarPath,
    String? deviceName,
  });

  Future<void> deleteProfile();
}
