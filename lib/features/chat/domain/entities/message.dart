import 'package:equatable/equatable.dart';

enum MessageType { text, image, audio, pdf, file }

enum MessageStatus { pending, delivered, read }

class Message extends Equatable {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final MessageType messageType;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.messageType,
    this.filePath,
    this.fileName,
    this.fileSize,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
  });

  MessageStatus get status {
    if (readAt != null) return MessageStatus.read;
    if (deliveredAt != null) return MessageStatus.delivered;
    return MessageStatus.pending;
  }

  @override
  List<Object?> get props => [
    id,
    senderId,
    receiverId,
    content,
    messageType,
    filePath,
    fileName,
    fileSize,
    createdAt,
    deliveredAt,
    readAt,
  ];
}

class Conversation extends Equatable {
  final String peerId;
  final String peerName;
  final String? peerAvatar;
  final List<Message> messages;
  final DateTime lastMessageTime;

  const Conversation({
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    required this.messages,
    required this.lastMessageTime,
  });

  @override
  List<Object?> get props => [
    peerId,
    peerName,
    peerAvatar,
    messages,
    lastMessageTime,
  ];
}
