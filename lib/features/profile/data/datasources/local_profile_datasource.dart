import 'package:lantern/core/database/database_service.dart';
import 'package:uuid/uuid.dart';

class ProfileModel {
  final String id;
  final String username;
  final String? avatarPath;
  final String deviceName;
  final String deviceId;
  final String? ipAddress;
  final int? port;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProfileModel({
    required this.id,
    required this.username,
    this.avatarPath,
    required this.deviceName,
    required this.deviceId,
    this.ipAddress,
    this.port,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'username': username,
    'avatar_path': avatarPath,
    'device_name': deviceName,
    'device_id': deviceId,
    'ip_address': ipAddress,
    'port': port,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ProfileModel.fromMap(Map<String, dynamic> map) => ProfileModel(
    id: map['id'] ?? '',
    username: map['username'] ?? '',
    avatarPath: map['avatar_path'],
    deviceName: map['device_name'] ?? '',
    deviceId: map['device_id'] ?? '',
    ipAddress: map['ip_address'],
    port: map['port'],
    createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(map['updated_at'] ?? '') ?? DateTime.now(),
  );
}

class LocalProfileDatasource {
  final DatabaseService _databaseService;

  LocalProfileDatasource(this._databaseService);

  Future<void> createProfile({
    required String username,
    required String deviceName,
    required String deviceId,
    String? avatarPath,
  }) async {
    final profile = ProfileModel(
      id: const Uuid().v4(),
      username: username,
      avatarPath: avatarPath,
      deviceName: deviceName,
      deviceId: deviceId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _databaseService.database.insert('profiles', profile.toMap());
  }

  Future<ProfileModel?> getProfile() async {
    final result = await _databaseService.database.query('profiles', limit: 1);
    if (result.isEmpty) return null;
    return ProfileModel.fromMap(result.first);
  }

  Future<void> updateProfile({
    String? username,
    String? avatarPath,
    String? deviceName,
  }) async {
    final profile = await getProfile();
    if (profile == null) throw Exception('Profile not found');

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (username != null) updates['username'] = username;
    if (avatarPath != null) updates['avatar_path'] = avatarPath;
    if (deviceName != null) updates['device_name'] = deviceName;

    await _databaseService.database.update(
      'profiles',
      updates,
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  Future<void> deleteProfile() async {
    await _databaseService.database.delete('profiles');
  }
}
