import 'package:lantern/features/profile/data/datasources/local_profile_datasource.dart';
import 'package:lantern/features/profile/domain/entities/profile.dart';
import 'package:lantern/features/profile/domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final LocalProfileDatasource _datasource;

  ProfileRepositoryImpl(this._datasource);

  @override
  Future<void> createProfile({
    required String username,
    required String deviceName,
    required String deviceId,
    String? avatarPath,
  }) async {
    return _datasource.createProfile(
      username: username,
      deviceName: deviceName,
      deviceId: deviceId,
      avatarPath: avatarPath,
    );
  }

  @override
  Future<Profile?> getProfile() async {
    final model = await _datasource.getProfile();
    if (model == null) return null;

    return Profile(
      id: model.id,
      username: model.username,
      avatarPath: model.avatarPath,
      deviceName: model.deviceName,
      deviceId: model.deviceId,
      ipAddress: model.ipAddress,
      port: model.port,
      createdAt: model.createdAt,
      updatedAt: model.updatedAt,
    );
  }

  @override
  Future<void> updateProfile({
    String? username,
    String? avatarPath,
    String? deviceName,
  }) async {
    return _datasource.updateProfile(
      username: username,
      avatarPath: avatarPath,
      deviceName: deviceName,
    );
  }

  @override
  Future<void> deleteProfile() async {
    return _datasource.deleteProfile();
  }
}
