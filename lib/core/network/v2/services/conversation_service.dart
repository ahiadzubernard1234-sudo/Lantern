import 'package:lantern/core/database/database_service.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import '../models/network_models.dart';
import 'discovery_service.dart';

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

/// One row in the Chats list: the latest message with a person.
class ConversationSummary {
  final String peerId;
  final String peerName;
  final String lastText;
  final bool lastIsMine;
  final DateTime time;

  const ConversationSummary({
    required this.peerId,
    required this.peerName,
    required this.lastText,
    required this.lastIsMine,
    required this.time,
  });
}

/// Loads saved conversations from the local database.
class ConversationService {
  static final ConversationService _instance = ConversationService._internal();
  factory ConversationService() => _instance;
  ConversationService._internal();

  final Logger _logger = Logger();

  bool _remembering = false;
  final Map<String, String> _savedPeers = {};

  /// Save the name and address of every peer we see, so their chats still
  /// show a name when they are offline or after a restart.
  void startRemembering() {
    if (_remembering) return;
    _remembering = true;
    DiscoveryService().addListener((peers) {
      for (final peer in peers) {
        _remember(peer);
      }
    });
  }

  Future<void> _remember(PeerInfo peer) async {
    final fingerprint =
        '${peer.username}|${peer.deviceName}|${peer.ipAddress}|${peer.port}';
    if (_savedPeers[peer.deviceId] == fingerprint) return;
    _savedPeers[peer.deviceId] = fingerprint;
    try {
      await DatabaseService().database.insert(
        'peers',
        {
          'id': peer.deviceId,
          'username': peer.username,
          'ip_address': peer.ipAddress,
          'port': peer.port,
          'device_id': peer.deviceId,
          'device_name': peer.deviceName,
          'last_seen': DateTime.now().toIso8601String(),
          'is_online': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      _logger.w('Could not remember peer ${peer.username}: $e');
    }
  }

  /// Last known name and device of a person (null if never seen).
  Future<PeerInfo?> savedPeer(String deviceId) async {
    try {
      final rows = await DatabaseService().database.query(
        'peers',
        where: 'device_id = ?',
        whereArgs: [deviceId],
        orderBy: 'last_seen DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final r = rows.first;
      return PeerInfo(
        deviceId: deviceId,
        username: (r['username'] as String?) ?? 'Unknown',
        deviceName: (r['device_name'] as String?) ?? '',
        ipAddress: (r['ip_address'] as String?) ?? '',
        port: (r['port'] as int?) ?? 15555,
        lastSeen: 0,
        isOnline: false,
      );
    } catch (e) {
      _logger.w('Could not read saved peer: $e');
      return null;
    }
  }

  /// Every conversation, newest first.
  Future<List<ConversationSummary>> listConversations(String myId) async {
    try {
      final db = DatabaseService().database;
      final rows = await db.rawQuery('''
        SELECT CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS peer_id,
               sender_id, content, created_at
        FROM messages
        WHERE message_type IN ('text', 'image')
          AND (sender_id = ? OR receiver_id = ?)
        ORDER BY created_at DESC
        LIMIT 2000
      ''', [myId, myId, myId]);

      final nameRows = await db.query('peers', columns: ['device_id', 'username']);
      final names = <String, String>{};
      for (final r in nameRows) {
        final id = r['device_id'] as String?;
        final name = r['username'] as String?;
        if (id != null && name != null) names[id] = name;
      }

      final seen = <String>{};
      final out = <ConversationSummary>[];
      for (final r in rows) {
        final peerId = r['peer_id'] as String;
        if (peerId == 'broadcast' || !seen.add(peerId)) continue;
        out.add(ConversationSummary(
          peerId: peerId,
          peerName: names[peerId] ?? 'Unknown device',
          lastText: r['content'] as String,
          lastIsMine: r['sender_id'] == myId,
          time: DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
        ));
      }
      return out;
    } catch (e) {
      _logger.e('Failed to list conversations: $e');
      return [];
    }
  }

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
