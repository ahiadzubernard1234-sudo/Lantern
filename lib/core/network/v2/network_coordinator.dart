import 'dart:async';
import 'package:logger/logger.dart';
import 'models/network_models.dart';
import 'services/discovery_service.dart';
import 'services/connection_manager.dart';
import 'services/message_service.dart';
import 'services/delivery_manager.dart';
import 'services/presence_manager.dart';
import 'services/room_manager.dart';
import 'services/file_transfer_service.dart';
import 'services/security_service.dart';
import 'services/network_monitor.dart';

class NetworkServiceCoordinator {
  static final NetworkServiceCoordinator _instance =
      NetworkServiceCoordinator._internal();

  final Logger _logger = Logger();

  late String _deviceId;
  late String _username;
  late String _deviceName;

  bool _initialized = false;
  late Timer _maintenanceTimer;

  // Services
  final discoveryService = DiscoveryService();
  final connectionManager = ConnectionManager();
  final messageService = MessageService();
  final deliveryManager = DeliveryManager();
  final presenceManager = PresenceManager();
  final roomManager = RoomManager();
  final fileTransferService = FileTransferService();
  final securityService = SecurityService();
  final networkMonitor = NetworkMonitor();

  factory NetworkServiceCoordinator() => _instance;
  NetworkServiceCoordinator._internal();

  /// Initialize all services
  Future<void> initialize({
    required String deviceId,
    required String username,
    required String deviceName,
  }) async {
    if (_initialized) return;

    try {
      _deviceId = deviceId;
      _username = username;
      _deviceName = deviceName;

      _logger.i('Initializing network services...');

      // Initialize services in order
      await securityService.initialize(deviceId: deviceId);
      await connectionManager.initialize(localDeviceId: deviceId);
      await networkMonitor.startMonitoring();

      // Wait for local IP
      await Future.delayed(const Duration(milliseconds: 500));
      final localIp = networkMonitor.getLocalIp() ?? 'unknown';

      // Start discovery
      await discoveryService.startDiscovery(
        deviceId: deviceId,
        username: username,
        deviceName: deviceName,
        ipAddress: localIp,
      );

      // Setup callbacks
      _setupCallbacks();

      // Start maintenance timer
      _maintenanceTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _performMaintenance(),
      );

      _initialized = true;
      _logger.i('Network services initialized successfully');
    } catch (e) {
      _logger.e('Failed to initialize network services: $e');
      rethrow;
    }
  }

  /// Setup service callbacks and wiring
  void _setupCallbacks() {
    // Connection manager receives messages
    connectionManager.addMessageCallback((message) {
      _handleReceivedMessage(message);
    });

    // Presence manager receives heartbeats
    discoveryService.addListener((peers) {
      for (final peer in peers) {
        if (!presenceManager._trackers.containsKey(peer.deviceId)) {
          presenceManager.initializePeer(
            deviceId: peer.deviceId,
            username: peer.username,
          );
        }
        presenceManager.recordHeartbeat(peer.deviceId);
      }
    });

    // Delivery manager status updates
    deliveryManager.addStatusCallback((delivery) {
      _logger.d('Delivery status: ${delivery.messageId} -> ${delivery.status}');
    });
  }

  /// Handle received message
  void _handleReceivedMessage(NetworkMessage message) {
    try {
      // Validate packet
      if (!securityService.validatePacket(message)) {
        _logger.w('Invalid packet received: ${message.id}');
        return;
      }

      // Handle based on type
      switch (message.type) {
        case MessageType.heartbeat:
          presenceManager.recordHeartbeat(message.senderId);
          break;

        case MessageType.ack:
          deliveryManager.handleAck(message.content, message.senderId);
          break;

        case MessageType.text:
        case MessageType.image:
          messageService.handleReceivedMessage(message);
          // Auto-send ACK
          _sendAck(message);
          break;

        case MessageType.file:
          // File transfer handled by UI layer
          _logger.d('File transfer packet received: ${message.metadata?['fileName']}');
          break;

        case MessageType.readReceipt:
          deliveryManager.markAsRead(
            messageId: message.content,
            senderId: message.senderId,
          );
          break;

        default:
          _logger.d('Unknown message type: ${message.type}');
      }
    } catch (e) {
      _logger.e('Error handling received message: $e');
    }
  }

  /// Send ACK for received message
  Future<void> _sendAck(NetworkMessage message) async {
    try {
      // Only ACK if we're the receiver
      if (message.receiverId != _deviceId) return;

      final ack = NetworkMessage(
        id: '${message.id}-ack',
        senderId: _deviceId,
        receiverId: message.senderId,
        type: MessageType.ack,
        content: message.id,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await connectionManager.sendMessage(
        message: ack,
        deviceId: message.senderId,
      );
    } catch (e) {
      _logger.w('Failed to send ACK: $e');
    }
  }

  /// Send text message to peer
  Future<void> sendMessage({
    required String recipientId,
    required String content,
  }) async {
    try {
      final message = NetworkMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: _deviceId,
        receiverId: recipientId,
        type: MessageType.text,
        content: securityService.sanitizeContent(content),
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Track delivery
      deliveryManager.trackMessage(
        message: message,
        recipientId: recipientId,
        sendFunction: () async {
          // Connect to peer if not already connected
          final peer = discoveryService.getPeerByDeviceId(recipientId);
          if (peer != null && !connectionManager.isConnectedTo(recipientId)) {
            await connectionManager.connectToPeer(
              ipAddress: peer.ipAddress,
              port: peer.port,
              deviceId: recipientId,
            );
          }

          // Send message
          await connectionManager.sendMessage(
            message: message,
            deviceId: recipientId,
          );
        },
      );

      // Save locally
      await messageService.sendMessage(
        message: message,
        sendFunction: (_) async {},
      );

      _logger.d('Message sent to $recipientId');
    } catch (e) {
      _logger.e('Failed to send message: $e');
      rethrow;
    }
  }

  /// Send message to room
  Future<void> sendRoomMessage({
    required String roomId,
    required String content,
  }) async {
    try {
      final room = roomManager.getRoom(roomId);
      if (room == null) throw Exception('Room not found');

      for (final memberId in room.memberIds) {
        if (memberId == _deviceId) continue; // Don't send to self

        await sendMessage(
          recipientId: memberId,
          content: content,
        );
      }

      _logger.d('Room message sent to ${room.memberIds.length - 1} members');
    } catch (e) {
      _logger.e('Failed to send room message: $e');
      rethrow;
    }
  }

  /// Perform periodic maintenance
  void _performMaintenance() {
    try {
      // Check for offline peers
      presenceManager.checkOfflinePeers();

      // Clean up old message IDs
      securityService.cleanupOldMessageIds();

      // Clean up completed file transfers
      fileTransferService.cleanupCompletedTransfers();

      // Clean up delivery manager
      deliveryManager.cleanupOldMessages();

      _logger.d('Maintenance completed');
    } catch (e) {
      _logger.e('Error during maintenance: $e');
    }
  }

  /// Get diagnostic information
  Map<String, dynamic> getDiagnostics() {
    return {
      'initialized': _initialized,
      'deviceId': _deviceId,
      'username': _username,
      'deviceName': _deviceName,
      'network': networkMonitor.getStats(),
      'peers': {
        'discovered': discoveryService.peerCount,
        'online': discoveryService.onlinePeerCount,
        'connected': connectionManager.connectionCount,
      },
      'messages': messageService.getStats(),
      'presence': presenceManager.getStats(),
      'rooms': roomManager.getStats(),
      'delivery': deliveryManager.getStats(),
      'fileTransfers': fileTransferService.getStats(),
      'security': securityService.getStats(),
    };
  }

  /// Shutdown all services
  Future<void> shutdown() async {
    try {
      _maintenanceTimer.cancel();

      await discoveryService.stopDiscovery();
      await connectionManager.shutdown();
      await networkMonitor.stopMonitoring();

      deliveryManager.shutdown();
      messageService.clearAll();
      presenceManager.clear();
      roomManager.clear();
      securityService.clear();

      _initialized = false;
      _logger.i('Network services shutdown complete');
    } catch (e) {
      _logger.e('Error during shutdown: $e');
    }
  }

  /// Check if initialized
  bool get isInitialized => _initialized;

  /// Get current device ID
  String get deviceId => _deviceId;

  /// Get current username
  String get username => _username;
}
