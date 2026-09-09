import 'package:equatable/equatable.dart';
import 'dart:convert';

/// Base network message structure for all communication
class NetworkMessage extends Equatable {
  final String id;
  final String senderId;
  final String receiverId;
  final String type;
  final String content;
  final int timestamp;
  final Map<String, dynamic>? metadata;

  const NetworkMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.content,
    required this.timestamp,
    this.metadata,
  });

  /// Convert to JSON for transmission
  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'receiverId': receiverId,
    'type': type,
    'content': content,
    'timestamp': timestamp,
    'metadata': metadata,
  };

  /// Parse from JSON
  factory NetworkMessage.fromJson(Map<String, dynamic> json) {
    return NetworkMessage(
      id: json['id'] ?? '',
      senderId: json['senderId'] ?? '',
      receiverId: json['receiverId'] ?? '',
      type: json['type'] ?? 'unknown',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] ?? 0,
      metadata: json['metadata'],
    );
  }

  /// Encode to bytes
  List<int> encode() {
    final jsonString = jsonEncode(toJson());
    return utf8.encode(jsonString);
  }

  /// Decode from bytes
  static NetworkMessage decode(List<int> bytes) {
    final jsonString = utf8.decode(bytes);
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return NetworkMessage.fromJson(json);
  }

  @override
  List<Object?> get props => [
    id,
    senderId,
    receiverId,
    type,
    content,
    timestamp,
    metadata,
  ];
}

/// Message type constants
class MessageType {
  static const String discovery = 'discovery';
  static const String heartbeat = 'heartbeat';
  static const String text = 'text';
  static const String image = 'image';
  static const String file = 'file';
  static const String ack = 'ack';
  static const String roomInvite = 'room_invite';
  static const String roomMessage = 'room_message';
  static const String readReceipt = 'read_receipt';
}

/// Peer information discovered on network
class PeerInfo extends Equatable {
  final String deviceId;
  final String username;
  final String deviceName;
  final String ipAddress;
  final int port;
  final int lastSeen;
  final bool isOnline;

  const PeerInfo({
    required this.deviceId,
    required this.username,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.lastSeen,
    required this.isOnline,
  });

  factory PeerInfo.fromJson(Map<String, dynamic> json) {
    return PeerInfo(
      deviceId: json['deviceId'] ?? '',
      username: json['username'] ?? '',
      deviceName: json['deviceName'] ?? '',
      ipAddress: json['ipAddress'] ?? '',
      port: json['port'] ?? 15555,
      lastSeen: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      isOnline: true,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'username': username,
    'deviceName': deviceName,
    'ipAddress': ipAddress,
    'port': port,
    'timestamp': lastSeen,
  };

  PeerInfo copyWith({
    String? deviceId,
    String? username,
    String? deviceName,
    String? ipAddress,
    int? port,
    int? lastSeen,
    bool? isOnline,
  }) {
    return PeerInfo(
      deviceId: deviceId ?? this.deviceId,
      username: username ?? this.username,
      deviceName: deviceName ?? this.deviceName,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  @override
  List<Object?> get props => [
    deviceId,
    username,
    deviceName,
    ipAddress,
    port,
    lastSeen,
    isOnline,
  ];
}

/// Delivery status enum
enum DeliveryStatus {
  pending,
  sent,
  delivered,
  read,
  failed,
}

/// Message delivery record
class MessageDelivery extends Equatable {
  final String messageId;
  final String recipientId;
  final DeliveryStatus status;
  final int createdAt;
  final int? deliveredAt;
  final int? readAt;

  const MessageDelivery({
    required this.messageId,
    required this.recipientId,
    required this.status,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
  });

  @override
  List<Object?> get props => [
    messageId,
    recipientId,
    status,
    createdAt,
    deliveredAt,
    readAt,
  ];
}

/// Room (group chat) information
class RoomInfo extends Equatable {
  final String roomId;
  final String name;
  final String? description;
  final String ownerId;
  final List<String> memberIds;
  final int createdAt;
  final int updatedAt;

  const RoomInfo({
    required this.roomId,
    required this.name,
    this.description,
    required this.ownerId,
    required this.memberIds,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
    roomId,
    name,
    description,
    ownerId,
    memberIds,
    createdAt,
    updatedAt,
  ];
}

/// File transfer session information
class FileTransferSession extends Equatable {
  final String sessionId;
  final String fileName;
  final int fileSize;
  final String senderDeviceId;
  final String receiverDeviceId;
  final int totalChunks;
  final int receivedChunks;
  final double progress;
  final bool isComplete;
  final bool isFailed;

  const FileTransferSession({
    required this.sessionId,
    required this.fileName,
    required this.fileSize,
    required this.senderDeviceId,
    required this.receiverDeviceId,
    required this.totalChunks,
    required this.receivedChunks,
    required this.progress,
    required this.isComplete,
    required this.isFailed,
  });

  @override
  List<Object?> get props => [
    sessionId,
    fileName,
    fileSize,
    senderDeviceId,
    receiverDeviceId,
    totalChunks,
    receivedChunks,
    progress,
    isComplete,
    isFailed,
  ];
}
