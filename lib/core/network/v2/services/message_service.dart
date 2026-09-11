import 'dart:async';
import 'package:logger/logger.dart';
import 'package:lantern/core/database/database_service.dart';
import 'package:sqflite/sqflite.dart';
import '../models/network_models.dart';

typedef MessageReceivedCallback = void Function(NetworkMessage message);

class MessageService {
  static final MessageService _instance = MessageService._internal();
  final Logger _logger = Logger();

  final List<MessageReceivedCallback> _receivedCallbacks = [];
  final Map<String, List<NetworkMessage>> _messageBuffer = {};
  final DatabaseService _database = DatabaseService();

  factory MessageService() => _instance;
  MessageService._internal();

  /// Send message to peer
  Future<void> sendMessage({
    required NetworkMessage message,
    required Future<void> Function(NetworkMessage) sendFunction,
  }) async {
    try {
      // Save to local database (would integrate with database service)
      await _saveMessageLocally(message, sent: true);

      // Send via network
      await sendFunction(message);

      _logger.d('Message sent: ${message.id} to ${message.receiverId}');
    } catch (e) {
      _logger.e('Failed to send message: $e');
      rethrow;
    }
  }

  /// Handle received message
  Future<void> handleReceivedMessage(NetworkMessage message) async {
    try {
      // Save to local database
      await _saveMessageLocally(message, sent: false);

      // Send ACK if this is a regular message (not heartbeat/ack)
      if (!_isSystemMessage(message)) {
        // ACK would be sent by delivery manager
      }

      // Notify listeners
      _notifyMessageReceived(message);

      _logger.d('Message received: ${message.id} from ${message.senderId}');
    } catch (e) {
      _logger.e('Failed to handle received message: $e');
    }
  }

  /// Save message locally (database integration point)
  Future<void> _saveMessageLocally(NetworkMessage message, {required bool sent}) async {
    try {
      final key = sent ? message.receiverId : message.senderId;
      _messageBuffer.putIfAbsent(key, () => []);
      if (!_messageBuffer[key]!.any((m) => m.id == message.id)) {
        _messageBuffer[key]!.add(message);
      }
      await _database.database.insert(
        'messages',
        {
          'id': message.id,
          'sender_id': message.senderId,
          'receiver_id': message.receiverId,
          'content': message.content,
          'message_type': message.type,
          'created_at': DateTime.fromMillisecondsSinceEpoch(message.timestamp).toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      _logger.d('Message persisted for $key');
    } catch (e) {
      _logger.e('Error saving message locally: $e');
    }
  }

  /// Get conversation with peer
  List<NetworkMessage> getConversation(String peerId) {
    return _messageBuffer[peerId] ?? [];
  }

  /// Clear conversation
  void clearConversation(String peerId) {
    _messageBuffer.remove(peerId);
    _logger.d('Conversation cleared for $peerId');
  }

  /// Add message received callback
  void addMessageCallback(MessageReceivedCallback callback) {
    _receivedCallbacks.add(callback);
  }

  /// Remove message received callback
  void removeMessageCallback(MessageReceivedCallback callback) {
    _receivedCallbacks.remove(callback);
  }

  /// Notify message received callbacks
  void _notifyMessageReceived(NetworkMessage message) {
    for (final callback in _receivedCallbacks) {
      try {
        callback(message);
      } catch (e) {
        _logger.e('Error in message callback: $e');
      }
    }
  }

  /// Check if message is system message (heartbeat, ack, etc)
  bool _isSystemMessage(NetworkMessage message) {
    return message.type == MessageType.heartbeat ||
        message.type == MessageType.ack ||
        message.type == MessageType.readReceipt;
  }

  /// Get message count for peer
  int getMessageCount(String peerId) {
    return _messageBuffer[peerId]?.length ?? 0;
  }

  /// Get all conversations
  Map<String, List<NetworkMessage>> getAllConversations() {
    return Map.from(_messageBuffer);
  }

  /// Clear all messages
  void clearAll() {
    _messageBuffer.clear();
    _logger.d('All messages cleared');
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    int total = 0;
    for (final messages in _messageBuffer.values) {
      total += messages.length;
    }

    return {
      'conversations': _messageBuffer.length,
      'totalMessages': total,
      'averagePerConversation': _messageBuffer.isNotEmpty ? total / _messageBuffer.length : 0,
    };
  }
}
