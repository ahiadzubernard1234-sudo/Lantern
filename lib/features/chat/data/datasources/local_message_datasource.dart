import 'package:lantern/core/database/database_service.dart';
import 'package:lantern/features/chat/domain/entities/message.dart';

class LocalMessageDatasource {
  final DatabaseService _databaseService;

  LocalMessageDatasource(this._databaseService);

  Future<void> saveMessage({
    required String id,
    required String senderId,
    required String receiverId,
    required String content,
    required String messageType,
    String? filePath,
    String? fileName,
    int? fileSize,
  }) async {
    await _databaseService.database.insert('messages', {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'message_type': messageType,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Message>> getConversation(String peerId, {String? currentUserId}) async {
    final results = await _databaseService.database.rawQuery(
      '''SELECT * FROM messages
         WHERE (sender_id = ? AND receiver_id = ?)
            OR (sender_id = ? AND receiver_id = ?)
         ORDER BY created_at ASC''',
      [currentUserId, peerId, peerId, currentUserId],
    );

    return results.map((map) => _mapToMessage(map)).toList();
  }

  Future<List<Conversation>> getAllConversations({required String currentUserId}) async {
    final results = await _databaseService.database.rawQuery(
      '''SELECT DISTINCT
           CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END as peer_id,
           MAX(created_at) as last_message_time
         FROM messages
         WHERE sender_id = ? OR receiver_id = ?
         GROUP BY peer_id
         ORDER BY last_message_time DESC''',
      [currentUserId, currentUserId, currentUserId],
    );

    final conversations = <Conversation>[];
    for (var result in results) {
      final peerId = result['peer_id'] as String;
      final messages = await getConversation(peerId, currentUserId: currentUserId);

      conversations.add(Conversation(
        peerId: peerId,
        peerName: '', // This should be fetched from peers table
        messages: messages,
        lastMessageTime: DateTime.tryParse(result['last_message_time'] as String) ?? DateTime.now(),
      ));
    }

    return conversations;
  }

  Future<void> markAsDelivered(String messageId) async {
    await _databaseService.database.update(
      'messages',
      {'delivered_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> markAsRead(String messageId) async {
    await _databaseService.database.update(
      'messages',
      {'read_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    await _databaseService.database.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> clearConversation(String peerId, {required String currentUserId}) async {
    await _databaseService.database.delete(
      'messages',
      where: '(sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)',
      whereArgs: [currentUserId, peerId, peerId, currentUserId],
    );
  }

  Message _mapToMessage(Map<String, dynamic> map) {
    return Message(
      id: map['id'] ?? '',
      senderId: map['sender_id'] ?? '',
      receiverId: map['receiver_id'] ?? '',
      content: map['content'] ?? '',
      messageType: _parseMessageType(map['message_type']),
      filePath: map['file_path'],
      fileName: map['file_name'],
      fileSize: map['file_size'],
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      deliveredAt: map['delivered_at'] != null ? DateTime.parse(map['delivered_at']) : null,
      readAt: map['read_at'] != null ? DateTime.parse(map['read_at']) : null,
    );
  }

  MessageType _parseMessageType(String? type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'audio':
        return MessageType.audio;
      case 'pdf':
        return MessageType.pdf;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }
}
