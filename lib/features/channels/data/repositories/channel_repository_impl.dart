import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:lantern/core/network/network_service.dart';
import 'package:lantern/features/channels/data/datasources/local_channel_datasource.dart';
import 'package:lantern/features/channels/domain/entities/channel.dart';
import 'package:lantern/features/channels/domain/repositories/channel_repository.dart';

class ChannelRepositoryImpl implements ChannelRepository {
  final LocalChannelDatasource _datasource;
  final Logger _logger = Logger();

  ChannelRepositoryImpl(this._datasource, NetworkService _);

  @override
  Future<void> createChannel({
    required String name,
    required String ownerId,
    String? description,
  }) async {
    return _datasource.createChannel(
      name: name,
      ownerId: ownerId,
      description: description,
    );
  }

  @override
  Future<List<Channel>> getChannels() async {
    return _datasource.getChannels();
  }

  @override
  Future<Channel?> getChannelById(String channelId) async {
    return _datasource.getChannelById(channelId);
  }

  @override
  Future<void> joinChannel(String channelId, String memberId) async {
    return _datasource.addChannelMember(channelId, memberId);
  }

  @override
  Future<void> leaveChannel(String channelId, String memberId) async {
    return _datasource.removeChannelMember(channelId, memberId);
  }

  @override
  Future<void> removeUserFromChannel(String channelId, String memberId) async {
    return _datasource.removeChannelMember(channelId, memberId);
  }

  @override
  Future<void> muteUser(String channelId, String memberId) async {
    return _datasource.muteChannelMember(channelId, memberId);
  }

  @override
  Future<void> unmuteUser(String channelId, String memberId) async {
    return _datasource.unmuteChannelMember(channelId, memberId);
  }

  @override
  Future<void> deleteChannel(String channelId) async {
    return _datasource.deleteChannel(channelId);
  }

  @override
  Future<List<ChannelMember>> getChannelMembers(String channelId) async {
    return _datasource.getChannelMembers(channelId);
  }

  @override
  Future<void> sendChannelMessage({
    required String channelId,
    required String senderId,
    required String content,
  }) async {
    // Save locally
    await _datasource.saveChannelMessage(
      channelId: channelId,
      senderId: senderId,
      content: content,
      messageType: 'text',
    );

    // Broadcast to all channel members
    try {
      final members = await _datasource.getChannelMembers(channelId);

      final messageData = {
        'type': 'channel_message',
        'channelId': channelId,
        'senderId': senderId,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final jsonData = jsonEncode(messageData);

      // In a real implementation, send to all members via their IP addresses
      _logger.d('Channel message sent to ${members.length} members: $jsonData');
    } catch (e) {
      _logger.e('Failed to send channel message: $e');
    }
  }

  @override
  Future<List<ChannelMessage>> getChannelMessages(String channelId) async {
    return _datasource.getChannelMessages(channelId);
  }
}
