import 'dart:convert';
import 'package:lantern/core/database/database_service.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import '../models/network_models.dart';

/// Persistent queue for messages that have not been delivered yet.
///
/// A message is saved when it is sent and removed once the peer ACKs it, so it
/// survives app restarts and peers being offline. The coordinator flushes the
/// queue whenever a peer shows up on the network again.
class OutboxService {
  static final OutboxService _instance = OutboxService._internal();
  factory OutboxService() => _instance;
  OutboxService._internal();

  final Logger _logger = Logger();

  static const int maxAttempts = 20;
  static const Duration maxAge = Duration(days: 7);

  Database get _db => DatabaseService().database;

  /// Save a message until it is delivered.
  Future<void> enqueue(NetworkMessage message) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.insert(
        'outbox',
        {
          'id': message.id,
          'receiver_id': message.receiverId,
          'payload': jsonEncode(message.toJson()),
          'created_at': now,
          'attempts': 1,
          'last_attempt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      _logger.e('Outbox enqueue failed: $e');
    }
  }

  /// Messages for a peer that are due for another attempt.
  Future<List<NetworkMessage>> dueFor(
    String deviceId, {
    Duration minGap = const Duration(seconds: 30),
  }) async {
    try {
      final cutoff = DateTime.now().millisecondsSinceEpoch - minGap.inMilliseconds;
      final rows = await _db.query(
        'outbox',
        where: 'receiver_id = ? AND attempts < ? AND last_attempt <= ?',
        whereArgs: [deviceId, maxAttempts, cutoff],
        orderBy: 'created_at ASC',
        limit: 50,
      );
      return rows
          .map((r) => NetworkMessage.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Outbox read failed: $e');
      return [];
    }
  }

  /// Record another delivery attempt.
  Future<void> markAttempt(String id) async {
    try {
      await _db.rawUpdate(
        'UPDATE outbox SET attempts = attempts + 1, last_attempt = ? WHERE id = ?',
        [DateTime.now().millisecondsSinceEpoch, id],
      );
    } catch (e) {
      _logger.e('Outbox update failed: $e');
    }
  }

  /// Remove a delivered message.
  Future<void> remove(String id) async {
    try {
      await _db.delete('outbox', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      _logger.e('Outbox remove failed: $e');
    }
  }

  /// Number of messages still waiting (all peers).
  Future<int> pendingCount() async {
    try {
      final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM outbox');
      return (rows.first['c'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Drop messages that are too old to keep retrying.
  Future<void> purge() async {
    try {
      final cutoff =
          DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
      await _db.delete('outbox', where: 'created_at < ?', whereArgs: [cutoff]);
    } catch (e) {
      _logger.e('Outbox purge failed: $e');
    }
  }
}
