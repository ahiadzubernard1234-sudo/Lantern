import 'package:equatable/equatable.dart';

class Profile extends Equatable {
  final String id;
  final String username;
  final String? avatarPath;
  final String deviceName;
  final String deviceId;
  final String? ipAddress;
  final int? port;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
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

  Profile copyWith({
    String? id,
    String? username,
    String? avatarPath,
    String? deviceName,
    String? deviceId,
    String? ipAddress,
    int? port,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Profile(
      id: id ?? this.id,
      username: username ?? this.username,
      avatarPath: avatarPath ?? this.avatarPath,
      deviceName: deviceName ?? this.deviceName,
      deviceId: deviceId ?? this.deviceId,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    username,
    avatarPath,
    deviceName,
    deviceId,
    ipAddress,
    port,
    createdAt,
    updatedAt,
  ];
}
