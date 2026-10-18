import 'package:lantern/core/database/database_service.dart';
import 'package:logger/logger.dart';

/// Delivery state of a message as shown in the chat UI.
enum ChatStatus { queued, sent, delivered }

/// A chat message ready to display.
class ChatMessage {
  final String id;
  final String text;
  final bool isMine;
  final DateTime time;
  final ChatStatus status;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isMine,
    required this.time,
    required this.status,
  });
}

/// Loads saved conversations from the local database.
class ConversationService {
  static final ConversationService _instance = ConversationService._internal();
  factory ConversationService() => _instance;
  ConversationService._internal();

  final Logger _logger = Logger();

  /// Messages between [myId] and [peerId], newest first.
  Future<List<ChatMessage>> load({
    required String myId,
    required String peerId,
    int limit = 300,
  }) async {
    try {
      final rows = await DatabaseService().database.rawQuery('''
        SELECT m.id, m.sender_id, m.content, m.created_at, m.delivered_at,
               EXISTS(SELECT 1 FROM outbox o WHERE o.id = m.id) AS queued
        FROM messages m
        WHERE m.message_type IN ('text', 'image')
          AND ((m.sender_id = ? AND m.receiver_id = ?)
            OR (m.sender_id = ? AND m.receiver_id = ?))
        ORDER BY m.created_at DESC
        LIMIT ?
      ''', [myId, peerId, peerId, myId, limit]);

      return rows.map((r) {
        final mine = r['sender_id'] == myId;
        var status = ChatStatus.delivered;
        if (mine) {
          if (r['delivered_at'] != null) {
            status = ChatStatus.delivered;
          } else if (((r['queued'] as int?) ?? 0) == 1) {
            status = ChatStatus.queued;
          } else {
            status = ChatStatus.sent;
          }
        }
        return ChatMessage(
          id: r['id'] as String,
          text: r['content'] as String,
          isMine: mine,
          time: DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
          status: status,
        );
      }).toList();
    } catch (e) {
      _logger.e('Failed to load conversation: $e');
      return [];
    }
  }
}
