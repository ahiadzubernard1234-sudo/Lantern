import 'package:equatable/equatable.dart';

class Channel extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final int memberCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Channel({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.memberCount,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    ownerId,
    memberCount,
    createdAt,
    updatedAt,
  ];
}

class ChannelMember extends Equatable {
  final String id;
  final String channelId;
  final String memberId;
  final DateTime joinedAt;
  final bool muted;

  const ChannelMember({
    required this.id,
    required this.channelId,
    required this.memberId,
    required this.joinedAt,
    required this.muted,
  });

  @override
  List<Object?> get props => [
    id,
    channelId,
    memberId,
    joinedAt,
    muted,
  ];
}

class ChannelMessage extends Equatable {
  final String id;
  final String channelId;
  final String senderId;
  final String content;
  final String messageType;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final DateTime createdAt;

  const ChannelMessage({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.content,
    required this.messageType,
    this.filePath,
    this.fileName,
    this.fileSize,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    id,
    channelId,
    senderId,
    content,
    messageType,
    filePath,
    fileName,
    fileSize,
    createdAt,
  ];
}
