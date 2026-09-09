import 'package:lantern/features/chat/domain/entities/message.dart';

abstract class MessageRepository {
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
    required String ipAddress,
    required int port,
  });

  Future<void> sendFile({
    required String senderId,
    required String receiverId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String ipAddress,
    required int port,
  });

  Future<List<Message>> getConversation(String peerId);

  Future<List<Conversation>> getAllConversations();

  Future<void> markAsDelivered(String messageId);

  Future<void> markAsRead(String messageId);

  Future<void> deleteMessage(String messageId);

  Future<void> clearConversation(String peerId);
}
