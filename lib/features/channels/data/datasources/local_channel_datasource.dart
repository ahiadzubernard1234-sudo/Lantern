import 'package:lantern/core/database/database_service.dart';
import 'package:lantern/features/channels/domain/entities/channel.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class LocalChannelDatasource {
  final DatabaseService _databaseService;

  LocalChannelDatasource(this._databaseService);

  Future<void> createChannel({
    required String name,
    required String ownerId,
    String? description,
  }) async {
    final channelId = const Uuid().v4();
    final now = DateTime.now();

    await _databaseService.database.insert('channels', {
      'id': channelId,
      'name': name,
      'description': description,
      'owner_id': ownerId,
      // The owner is inserted below; start at zero so it is counted once.
      'member_count': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    // Add owner as first member
    await addChannelMember(channelId, ownerId);
  }

  Future<List<Channel>> getChannels() async {
    final results = await _databaseService.database.query('channels');
    return results.map((map) => _mapToChannel(map)).toList();
  }

  Future<Channel?> getChannelById(String channelId) async {
    final results = await _databaseService.database.query(
      'channels',
      where: 'id = ?',
      whereArgs: [channelId],
    );

    if (results.isEmpty) return null;
    return _mapToChannel(results.first);
  }

  Future<void> addChannelMember(String channelId, String memberId) async {
    final memberId_ = const Uuid().v4();

    final inserted = await _databaseService.database.insert(
      'channel_members',
      {
        'id': memberId_,
        'channel_id': channelId,
        'member_id': memberId,
        'joined_at': DateTime.now().toIso8601String(),
        'muted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (inserted != 0) {
      await _databaseService.database.rawUpdate(
        'UPDATE channels SET member_count = member_count + 1 WHERE id = ?',
        [channelId],
      );
    }
  }

  Future<void> removeChannelMember(String channelId, String memberId) async {
    final deleted = await _databaseService.database.delete(
      'channel_members',
      where: 'channel_id = ? AND member_id = ?',
      whereArgs: [channelId, memberId],
    );

    if (deleted > 0) {
      await _databaseService.database.rawUpdate(
        'UPDATE channels SET member_count = MAX(0, member_count - 1) WHERE id = ?',
        [channelId],
      );
    }
  }

  Future<void> muteChannelMember(String channelId, String memberId) async {
    await _databaseService.database.update(
      'channel_members',
      {'muted': 1},
      where: 'channel_id = ? AND member_id = ?',
      whereArgs: [channelId, memberId],
    );
  }

  Future<void> unmuteChannelMember(String channelId, String memberId) async {
    await _databaseService.database.update(
      'channel_members',
      {'muted': 0},
      where: 'channel_id = ? AND member_id = ?',
      whereArgs: [channelId, memberId],
    );
  }

  Future<void> deleteChannel(String channelId) async {
    // Delete channel messages
    await _databaseService.database.delete(
      'channel_messages',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );

    // Delete channel members
    await _databaseService.database.delete(
      'channel_members',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );

    // Delete channel
    await _databaseService.database.delete(
      'channels',
      where: 'id = ?',
      whereArgs: [channelId],
    );
  }

  Future<List<ChannelMember>> getChannelMembers(String channelId) async {
    final results = await _databaseService.database.query(
      'channel_members',
      where: 'channel_id = ?',
      whereArgs: [channelId],
    );

    return results.map((map) => _mapToChannelMember(map)).toList();
  }

  Future<void> saveChannelMessage({
    required String channelId,
    required String senderId,
    required String content,
    required String messageType,
    String? filePath,
    String? fileName,
    int? fileSize,
  }) async {
    final messageId = const Uuid().v4();

    await _databaseService.database.insert('channel_messages', {
      'id': messageId,
      'channel_id': channelId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<ChannelMessage>> getChannelMessages(String channelId) async {
    final results = await _databaseService.database.query(
      'channel_messages',
      where: 'channel_id = ?',
      whereArgs: [channelId],
      orderBy: 'created_at ASC',
    );

    return results.map((map) => _mapToChannelMessage(map)).toList();
  }

  Channel _mapToChannel(Map<String, dynamic> map) {
    return Channel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      ownerId: map['owner_id'] ?? '',
      memberCount: map['member_count'] ?? 0,
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  ChannelMember _mapToChannelMember(Map<String, dynamic> map) {
    return ChannelMember(
      id: map['id'] ?? '',
      channelId: map['channel_id'] ?? '',
      memberId: map['member_id'] ?? '',
      joinedAt: DateTime.tryParse(map['joined_at'] ?? '') ?? DateTime.now(),
      muted: (map['muted'] as int?) == 1,
    );
  }

  ChannelMessage _mapToChannelMessage(Map<String, dynamic> map) {
    return ChannelMessage(
      id: map['id'] ?? '',
      channelId: map['channel_id'] ?? '',
      senderId: map['sender_id'] ?? '',
      content: map['content'] ?? '',
      messageType: map['message_type'] ?? 'text',
      filePath: map['file_path'],
      fileName: map['file_name'],
      fileSize: map['file_size'],
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}
