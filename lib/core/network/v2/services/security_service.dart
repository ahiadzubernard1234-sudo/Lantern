import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'network_models.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  final Logger _logger = Logger();

  late String _deviceToken;
  late String _localDeviceId;
  final Set<String> _seenMessageIds = {};

  static const int TOKEN_LENGTH = 32;
  static const int MESSAGE_REPLAY_WINDOW_SECONDS = 300; // 5 minutes

  factory SecurityService() => _instance;
  SecurityService._internal();

  /// Initialize security service
  Future<void> initialize({required String deviceId}) async {
    try {
      _localDeviceId = deviceId;
      _deviceToken = _generateDeviceToken();
      _logger.i('Security service initialized with token: ${_deviceToken.substring(0, 8)}...');
    } catch (e) {
      _logger.e('Failed to initialize security service: $e');
      rethrow;
    }
  }

  /// Generate unique device token
  String _generateDeviceToken() {
    final random = const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final combined = '$random-$timestamp';
    return sha256.convert(utf8.encode(combined)).toString().substring(0, TOKEN_LENGTH);
  }

  /// Get device token
  String getDeviceToken() => _deviceToken;

  /// Validate message packet
  bool validatePacket(NetworkMessage message) {
    try {
      // Check required fields
      if (message.id.isEmpty ||
          message.senderId.isEmpty ||
          message.receiverId.isEmpty ||
          message.type.isEmpty) {
        _logger.w('Invalid packet: missing required fields');
        return false;
      }

      // Check message size (max 100KB)
      final encoded = message.encode();
      if (encoded.length > 102400) {
        _logger.w('Invalid packet: message too large (${encoded.length} bytes)');
        return false;
      }

      // Check timestamp is within range
      final now = DateTime.now().millisecondsSinceEpoch;
      final messageAge = now - message.timestamp;
      if (messageAge > MESSAGE_REPLAY_WINDOW_SECONDS * 1000) {
        _logger.w('Invalid packet: message too old (${messageAge}ms)');
        return false;
      }

      // Check for replay attacks
      if (_seenMessageIds.contains(message.id)) {
        _logger.w('Invalid packet: duplicate message ID (replay attack?)');
        return false;
      }

      _seenMessageIds.add(message.id);
      return true;
    } catch (e) {
      _logger.e('Error validating packet: $e');
      return false;
    }
  }

  /// Sanitize message content
  String sanitizeContent(String content) {
    try {
      // Remove null bytes
      content = content.replaceAll('\x00', '');

      // Limit length to 10KB
      if (content.length > 10240) {
        content = content.substring(0, 10240);
      }

      return content.trim();
    } catch (e) {
      _logger.e('Error sanitizing content: $e');
      return '';
    }
  }

  /// Hash sensitive data
  String hashData(String data) {
    return sha256.convert(utf8.encode(data)).toString();
  }

  /// Verify device identity
  bool verifyDeviceId(String deviceId) {
    // Device ID should be non-empty and not equal to ours
    return deviceId.isNotEmpty && deviceId != _localDeviceId;
  }

  /// Get security statistics
  Map<String, dynamic> getStats() {
    return {
      'deviceId': _localDeviceId,
      'tokenPrefix': _deviceToken.substring(0, 8),
      'seenMessages': _seenMessageIds.length,
      'replayWindowSeconds': MESSAGE_REPLAY_WINDOW_SECONDS,
    };
  }

  /// Clean old message IDs to prevent memory leak
  void cleanupOldMessageIds() {
    // Keep only recent message IDs (last 1000)
    if (_seenMessageIds.length > 1000) {
      final toRemove = _seenMessageIds.length - 1000;
      _seenMessageIds.removeWhere((_) => toRemove-- > 0);
      _logger.d('Cleaned up old message IDs');
    }
  }

  /// Clear all security data
  void clear() {
    _seenMessageIds.clear();
    _logger.d('Security service cleared');
  }
}
