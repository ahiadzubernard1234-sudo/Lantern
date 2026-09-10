import 'package:lantern/features/channels/domain/entities/channel.dart';

abstract class ChannelRepository {
  Future<void> createChannel({
    required String name,
    required String ownerId,
    String? description,
  });

  Future<List<Channel>> getChannels();

  Future<Channel?> getChannelById(String channelId);

  Future<void> joinChannel(String channelId, String memberId);

  Future<void> leaveChannel(String channelId, String memberId);

  Future<void> removeUserFromChannel(String channelId, String memberId);

  Future<void> muteUser(String channelId, String memberId);

  Future<void> unmuteUser(String channelId, String memberId);

  Future<void> deleteChannel(String channelId);

  Future<List<ChannelMember>> getChannelMembers(String channelId);

  Future<void> sendChannelMessage({
    required String channelId,
    required String senderId,
    required String content,
  });

  Future<List<ChannelMessage>> getChannelMessages(String channelId);
}
