import 'dart:async';
import 'package:logger/logger.dart';
import '../models/network_models.dart';

class DeliveryManager {
  static final DeliveryManager _instance = DeliveryManager._internal();
  final Logger _logger = Logger();

  final Map<String, _PendingDelivery> _pendingMessages = {};
  final List<DeliveryStatusCallback> _statusCallbacks = [];

  static const int MAX_RETRIES = 3;
  static const int ACK_TIMEOUT_SECONDS = 5;
  static const int RETRY_DELAY_SECONDS = 2;

  factory DeliveryManager() => _instance;
  DeliveryManager._internal();

  /// Track message for delivery
  void trackMessage({
    required NetworkMessage message,
    required String recipientId,
    required Future<void> Function() sendFunction,
  }) {
    if (_pendingMessages.containsKey(message.id)) {
      _logger.d('Message ${message.id} is already being delivered');
      return;
    }

    final pending = _PendingDelivery(
      messageId: message.id,
      recipientId: recipientId,
      message: message,
      sendFunction: sendFunction,
      createdAt: DateTime.now(),
    );

    _pendingMessages[message.id] = pending;

    // Send message and wait for ACK
    _sendWithRetry(message.id);
  }

  /// Forget a message, but only if it is still the one we are tracking
  void _removePending(_PendingDelivery pending) {
    if (identical(_pendingMessages[pending.messageId], pending)) {
      _pendingMessages.remove(pending.messageId);
    }
  }

  void _finishDelivered(_PendingDelivery pending) {
    _updateDeliveryStatus(
      messageId: pending.messageId,
      recipientId: pending.recipientId,
      status: DeliveryStatus.delivered,
    );
    _removePending(pending);
    _logger.d('Message delivered: ${pending.messageId}');
  }

  /// Send message with retry logic
  Future<void> _sendWithRetry(String messageId) async {
    final pending = _pendingMessages[messageId];
    if (pending == null) return;

    // An ACK already arrived (for example a late one from an earlier try)
    if (pending.acked) {
      _finishDelivered(pending);
      return;
    }

    if (pending.retryCount >= MAX_RETRIES) {
      _updateDeliveryStatus(
        messageId: messageId,
        recipientId: pending.recipientId,
        status: DeliveryStatus.failed,
      );
      _removePending(pending);
      _logger.w('Message delivery failed after $MAX_RETRIES tries: $messageId');
      return;
    }

    try {
      // Create the waiter BEFORE sending, so a very fast ACK is never missed
      final completer = Completer<bool>();
      pending.ackCompleter = completer;

      // Send message
      await pending.sendFunction();

      // Update status to sent
      _updateDeliveryStatus(
        messageId: messageId,
        recipientId: pending.recipientId,
        status: DeliveryStatus.sent,
      );

      // Wait for ACK with timeout
      final ackReceived = pending.acked ||
          await completer.future.timeout(
            const Duration(seconds: ACK_TIMEOUT_SECONDS),
            onTimeout: () => false,
          );

      if (ackReceived || pending.acked) {
        _finishDelivered(pending);
      } else {
        // ACK timeout, retry
        pending.retryCount++;
        _logger.w('No ACK for $messageId, retrying (${pending.retryCount}/$MAX_RETRIES)');

        // Wait before retry
        await Future.delayed(
          Duration(seconds: RETRY_DELAY_SECONDS * pending.retryCount),
        );

        await _sendWithRetry(messageId);
      }
    } catch (e) {
      pending.retryCount++;
      _logger.w('Error sending message $messageId: $e (try ${pending.retryCount}/$MAX_RETRIES)');

      await Future.delayed(
        Duration(seconds: RETRY_DELAY_SECONDS * pending.retryCount),
      );

      await _sendWithRetry(messageId);
    }
  }

  /// Handle ACK receipt
  void handleAck(String messageId, String senderId) {
    final pending = _pendingMessages[messageId];
    if (pending == null) {
      _logger.d('ACK for $messageId from $senderId (not being tracked)');
      return;
    }
    pending.acked = true;
    final waiter = pending.ackCompleter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(true);
    }
    _logger.i('ACK received for message $messageId from $senderId');
  }

  /// Send ACK for received message
  Future<void> sendAck({
    required String messageId,
    required String recipientId,
    required Future<void> Function() sendFunction,
  }) async {
    try {
      await sendFunction();
      _logger.d('ACK sent for message: $messageId');
    } catch (e) {
      _logger.e('Failed to send ACK for $messageId: $e');
    }
  }

  /// Mark message as read
  void markAsRead({
    required String messageId,
    required String senderId,
  }) {
    final delivery = _getPendingDelivery(messageId);
    if (delivery != null) {
      _updateDeliveryStatus(
        messageId: messageId,
        recipientId: senderId,
        status: DeliveryStatus.read,
      );
    }
  }

  /// Get delivery status
  DeliveryStatus? getDeliveryStatus(String messageId) {
    return _getPendingDelivery(messageId)?.status;
  }

  /// Get all pending messages
  List<_PendingDelivery> getPendingMessages() {
    return _pendingMessages.values.toList();
  }

  /// Add status callback
  void addStatusCallback(DeliveryStatusCallback callback) {
    _statusCallbacks.add(callback);
  }

  /// Remove status callback
  void removeStatusCallback(DeliveryStatusCallback callback) {
    _statusCallbacks.remove(callback);
  }

  /// Update delivery status and notify callbacks
  void _updateDeliveryStatus({
    required String messageId,
    required String recipientId,
    required DeliveryStatus status,
  }) {
    final pending = _pendingMessages[messageId];
    if (pending != null) {
      pending.status = status;

      final delivery = MessageDelivery(
        messageId: messageId,
        recipientId: recipientId,
        status: status,
        createdAt: pending.createdAt.millisecondsSinceEpoch,
        deliveredAt: status == DeliveryStatus.delivered || status == DeliveryStatus.read
            ? DateTime.now().millisecondsSinceEpoch
            : null,
        readAt: status == DeliveryStatus.read
            ? DateTime.now().millisecondsSinceEpoch
            : null,
      );

      // Notify callbacks
      for (final callback in _statusCallbacks) {
        try {
          callback(delivery);
        } catch (e) {
          _logger.e('Error in status callback: $e');
        }
      }
    }
  }

  /// Get pending delivery by message ID
  _PendingDelivery? _getPendingDelivery(String messageId) {
    return _pendingMessages[messageId];
  }

  /// Clear failed messages older than 24 hours
  void cleanupOldMessages() {
    final now = DateTime.now();
    final oldMessages = _pendingMessages.entries
        .where((e) => now.difference(e.value.createdAt).inHours > 24)
        .map((e) => e.key)
        .toList();

    for (final messageId in oldMessages) {
      _pendingMessages.remove(messageId);
    }

    _logger.d('Cleaned up ${oldMessages.length} old messages');
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    final total = _pendingMessages.length;
    final pending = _pendingMessages.values
        .where((p) => p.status == DeliveryStatus.pending)
        .length;
    final sent = _pendingMessages.values
        .where((p) => p.status == DeliveryStatus.sent)
        .length;

    return {
      'total': total,
      'pending': pending,
      'sent': sent,
      'avgRetries': total > 0
          ? _pendingMessages.values
                  .map((p) => p.retryCount)
                  .reduce((a, b) => a + b) /
              total
          : 0,
    };
  }

  /// Shutdown delivery manager
  void shutdown() {
    _pendingMessages.clear();
    _statusCallbacks.clear();
    _logger.i('Delivery manager shutdown');
  }
}

/// Callback for delivery status changes
typedef DeliveryStatusCallback = void Function(MessageDelivery delivery);

/// Internal pending delivery tracking
class _PendingDelivery {
  final String messageId;
  final String recipientId;
  final NetworkMessage message;
  final Future<void> Function() sendFunction;
  final DateTime createdAt;

  DeliveryStatus status = DeliveryStatus.pending;
  int retryCount = 0;
  bool acked = false;
  Completer<bool>? ackCompleter;

  _PendingDelivery({
    required this.messageId,
    required this.recipientId,
    required this.message,
    required this.sendFunction,
    required this.createdAt,
  });
}
