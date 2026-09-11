import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:lantern/core/network/network_service.dart';
import 'package:lantern/features/chat/data/datasources/local_message_datasource.dart';
import 'package:lantern/features/chat/domain/entities/message.dart';
import 'package:lantern/features/chat/domain/repositories/message_repository.dart';
import 'package:lantern/features/profile/data/datasources/local_profile_datasource.dart';
import 'package:uuid/uuid.dart';

class MessageRepositoryImpl implements MessageRepository {
  final LocalMessageDatasource _datasource;
  final NetworkService _networkService;
  final Logger _logger = Logger();
  final LocalProfileDatasource? _profileDatasource;

  MessageRepositoryImpl(this._datasource, this._networkService, [this._profileDatasource]);

  @override
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
    required String ipAddress,
    required int port,
  }) async {
    final messageId = const Uuid().v4();

    // Save locally
    await _datasource.saveMessage(
      id: messageId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      messageType: 'text',
    );

    // Send to peer
    try {
      final messageData = {
        'type': 'message',
        'id': messageId,
        'senderId': senderId,
        'receiverId': receiverId,
        'content': content,
        'messageType': 'text',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final jsonData = jsonEncode(messageData);
      final encodedData = utf8.encode(jsonData);

      await _networkService.sendMessageToPeer(ipAddress, port, encodedData);
      await _datasource.markAsDelivered(messageId);
    } catch (e) {
      _logger.e('Failed to send message: $e');
      rethrow;
    }
  }

  @override
  Future<void> sendFile({
    required String senderId,
    required String receiverId,
    required String filePath,
    required String fileName,
    required int fileSize,
    required String ipAddress,
    required int port,
  }) async {
    final messageId = const Uuid().v4();
    final messageType = _getMessageType(fileName);

    // Save metadata locally
    await _datasource.saveMessage(
      id: messageId,
      senderId: senderId,
      receiverId: receiverId,
      content: 'File: $fileName',
      messageType: messageType,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
    );

    // Send file to peer
    try {
      final file = File(filePath);
      final fileBytes = await file.readAsBytes();

      final fileData = {
        'type': 'file',
        'id': messageId,
        'senderId': senderId,
        'receiverId': receiverId,
        'fileName': fileName,
        'fileSize': fileSize,
        'fileBytes': base64Encode(fileBytes),
        'timestamp': DateTime.now().toIso8601String(),
      };

      final jsonData = jsonEncode(fileData);
      final encodedData = utf8.encode(jsonData);

      await _networkService.sendMessageToPeer(ipAddress, port, encodedData);
      await _datasource.markAsDelivered(messageId);
    } catch (e) {
      _logger.e('Failed to send file: $e');
      rethrow;
    }
  }

  @override
  Future<List<Message>> getConversation(String peerId) async {
    final profile = await _profileDatasource?.getProfile();
    if (profile == null) return const [];
    return _datasource.getConversation(peerId, currentUserId: profile.id);
  }

  @override
  Future<List<Conversation>> getAllConversations() async {
    final profile = await _profileDatasource?.getProfile();
    if (profile == null) return const [];
    return _datasource.getAllConversations(currentUserId: profile.id);
  }

  @override
  Future<void> markAsDelivered(String messageId) async {
    return _datasource.markAsDelivered(messageId);
  }

  @override
  Future<void> markAsRead(String messageId) async {
    return _datasource.markAsRead(messageId);
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    return _datasource.deleteMessage(messageId);
  }

  @override
  Future<void> clearConversation(String peerId) async {
    final profile = await _profileDatasource?.getProfile();
    if (profile == null) return;
    return _datasource.clearConversation(peerId, currentUserId: profile.id);
  }

  String _getMessageType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return 'image';
      case 'mp3':
      case 'wav':
      case 'm4a':
        return 'audio';
      case 'pdf':
        return 'pdf';
      default:
        return 'file';
    }
  }
}
