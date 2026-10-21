import 'dart:async';
import 'package:lantern/core/database/database_service.dart';
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
import 'services/crypto_service.dart';
import 'services/outbox_service.dart';

class NetworkServiceCoordinator {
  static final NetworkServiceCoordinator _instance =
      NetworkServiceCoordinator._internal();

  final Logger _logger = Logger();

  late String _deviceId;
  late String _username;
  late String _deviceName;

  bool _initialized = false;
  bool _initializing = false;
  String? _lastInitError;
  Map<String, String>? _initArgs;
  Timer? _maintenanceTimer;
  bool _callbacksSetUp = false;
  StreamSubscription<TrustAlert>? _trustAlertSub;

  // Messages currently being sent, and peers whose outbox is being flushed
  final Set<String> _inFlight = {};
  final Set<String> _flushing = {};

  // Chat messages we already accepted (lets us re-ACK duplicates)
  final Map<String, DateTime> _recentReceived = {};

  // Fires whenever a chat message is received, sent, or changes delivery state
  final StreamController<void> _chatChanges = StreamController<void>.broadcast();

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
  final cryptoService = CryptoService();
  final outboxService = OutboxService();

  factory NetworkServiceCoordinator() => _instance;
  NetworkServiceCoordinator._internal();

  /// Peers whose identity key changed (show a warning in the UI).
  Stream<TrustAlert> get trustAlerts => cryptoService.alerts;

  /// Emits whenever a conversation may need to be reloaded.
  Stream<void> get chatChanges => _chatChanges.stream;

  /// Why the last start-up attempt failed (null if it did not fail).
  String? get lastInitError => _lastInitError;

  /// Initialize all services
  Future<void> initialize({
    required String deviceId,
    required String username,
    required String deviceName,
  }) async {
    if (_initialized || _initializing) return;
    _initializing = true;
    _initArgs = {
      'deviceId': deviceId,
      'username': username,
      'deviceName': deviceName,
    };

    try {
      _deviceId = deviceId;
      _username = username;
      _deviceName = deviceName;
      _lastInitError = null;

      _logger.i('Starting network services as "$username" ($deviceName)');

      // Initialize services in order
      await securityService.initialize(deviceId: deviceId);
      _logger.i('Step 1/5: security service ready');

      await cryptoService.initialize();
      _logger.i('Step 2/5: encryption identity ready (${cryptoService.localFingerprint})');

      await connectionManager.initialize(localDeviceId: deviceId);
      _logger.i('Step 3/5: message server listening on TCP port ${ConnectionManager.SERVER_PORT}');

      await networkMonitor.startMonitoring();
      _logger.i('Step 4/5: network check: ${networkMonitor.statusMessage}');

      final localIp = networkMonitor.getLocalIp() ?? 'unknown';

      // Start discovery
      await discoveryService.startDiscovery(
        deviceId: deviceId,
        username: username,
        deviceName: deviceName,
        ipAddress: localIp,
        broadcastAddressProvider: networkMonitor.getBroadcastAddress,
      );
      _logger.i('Step 5/5: peer discovery started');

      // Setup callbacks
      _setupCallbacks();

      // Start maintenance timer
      _maintenanceTimer?.cancel();
      _maintenanceTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _performMaintenance(),
      );

      _initialized = true;
      _logger.i('Network services initialized successfully');
    } catch (e) {
      _lastInitError = e.toString();
      _logger.e('Failed to initialize network services: $e');
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  /// Try starting the network again after a failure
  Future<void> retryInitialize() async {
    if (_initialized || _initializing) return;
    final args = _initArgs;
    if (args == null) return;
    _logger.i('Retrying network start-up');
    try {
      await initialize(
        deviceId: args['deviceId']!,
        username: args['username']!,
        deviceName: args['deviceName']!,
      );
    } catch (_) {
      // Already logged and stored in lastInitError
    }
  }

  /// Setup service callbacks and wiring
  void _setupCallbacks() {
    if (_callbacksSetUp) return;
    _callbacksSetUp = true;

    // Connection manager receives messages
    connectionManager.addMessageCallback((message) {
      _handleReceivedMessage(message);
    });

    // Saved incoming messages refresh open chats
    messageService.addMessageCallback((_) => _chatChanges.add(null));

    // Presence manager receives heartbeats; deliver queued messages to peers
    discoveryService.addListener((peers) {
      for (final peer in peers) {
        presenceManager.initializePeer(
          deviceId: peer.deviceId,
          username: peer.username,
        );
        presenceManager.recordHeartbeat(peer.deviceId);
        unawaited(_flushOutboxFor(peer.deviceId));
      }
    });

    // Delivery manager status updates
    deliveryManager.addStatusCallback((delivery) {
      _logger.d('Delivery status: ${delivery.messageId} -> ${delivery.status}');
      switch (delivery.status) {
        case DeliveryStatus.delivered:
        case DeliveryStatus.read:
          _inFlight.remove(delivery.messageId);
          unawaited(_onDelivered(delivery.messageId));
          break;
        case DeliveryStatus.failed:
          // Stays in the outbox and is retried when the peer is back
          _inFlight.remove(delivery.messageId);
          _chatChanges.add(null);
          break;
        default:
          _chatChanges.add(null);
          break;
      }
    });

    _trustAlertSub = cryptoService.alerts.listen((alert) {
      _logger.w('Identity key changed for ${alert.deviceId}: '
          '${alert.oldFingerprint} -> ${alert.newFingerprint}');
    });
  }

  /// A message was ACKed: drop it from the outbox and record delivery time
  Future<void> _onDelivered(String messageId) async {
    await outboxService.remove(messageId);
    try {
      await DatabaseService().database.update(
        'messages',
        {'delivered_at': DateTime.now().toIso8601String()},
        where: 'id = ? AND delivered_at IS NULL',
        whereArgs: [messageId],
      );
    } catch (e) {
      _logger.w('Could not record delivery time: $e');
    }
    _chatChanges.add(null);
  }

  /// Handle received message
  void _handleReceivedMessage(NetworkMessage message) {
    try {
      final isChat = message.type == MessageType.text ||
          message.type == MessageType.image;

      // A resend of something we already accepted: just ACK again
      if (isChat &&
          message.receiverId == _deviceId &&
          _recentReceived.containsKey(message.id)) {
        _sendAck(message);
        return;
      }

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
          _recentReceived[message.id] = DateTime.now();
          messageService.handleReceivedMessage(_restoreOriginalTimestamp(message));
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

  /// Queued messages are resent with a fresh timestamp; show the original one.
  NetworkMessage _restoreOriginalTimestamp(NetworkMessage message) {
    final original = message.metadata?['originalTimestamp'];
    if (original is! int || original <= 0 || original > message.timestamp) {
      return message;
    }
    return NetworkMessage(
      id: message.id,
      senderId: message.senderId,
      receiverId: message.receiverId,
      type: message.type,
      content: message.content,
      timestamp: original,
      metadata: message.metadata,
    );
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

  /// Send text message to peer.
  ///
  /// The message is saved to the persistent outbox first, so it is still
  /// delivered later if the peer is offline or the app restarts.
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

      await outboxService.enqueue(message);

      // Save locally first so it shows up in the chat right away
      await messageService.sendMessage(
        message: message,
        sendFunction: (_) async {},
      );
      _chatChanges.add(null);

      _dispatch(message);

      _logger.i('Message queued for $recipientId');
    } catch (e) {
      _logger.e('Failed to send message: $e');
      rethrow;
    }
  }

  /// Hand a message to the delivery manager (ACK tracking and retries)
  void _dispatch(NetworkMessage message) {
    final recipientId = message.receiverId;
    _inFlight.add(message.id);

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
  }

  /// Resend queued messages to a peer that is online
  Future<void> _flushOutboxFor(String deviceId) async {
    if (!_flushing.add(deviceId)) return;
    try {
      final due = await outboxService.dueFor(deviceId);
      for (final queued in due) {
        if (_inFlight.contains(queued.id)) continue;

        // Fresh timestamp so the receiver's replay window accepts it; the
        // original time travels in metadata.
        final fresh = NetworkMessage(
          id: queued.id,
          senderId: queued.senderId,
          receiverId: queued.receiverId,
          type: queued.type,
          content: queued.content,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          metadata: {
            ...?queued.metadata,
            'originalTimestamp': queued.timestamp,
          },
        );

        await outboxService.markAttempt(queued.id);
        _dispatch(fresh);
      }
    } catch (e) {
      _logger.w('Outbox flush failed for $deviceId: $e');
    } finally {
      _flushing.remove(deviceId);
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

  /// Fingerprint of this device's identity (for "verify safety number" screens)
  String get localFingerprint => cryptoService.localFingerprint;

  /// Fingerprint of a peer's pinned identity, or null if not seen yet
  Future<String?> peerFingerprint(String deviceId) =>
      cryptoService.peerFingerprint(deviceId);

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

      // Drop queued messages that are too old, and old duplicate-ACK records
      unawaited(outboxService.purge());
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      _recentReceived.removeWhere((_, seenAt) => seenAt.isBefore(cutoff));

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
      'identityFingerprint': cryptoService.localFingerprint,
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
      _maintenanceTimer?.cancel();
      await _trustAlertSub?.cancel();
      _trustAlertSub = null;

      await discoveryService.stopDiscovery();
      await connectionManager.shutdown();
      await networkMonitor.stopMonitoring();

      deliveryManager.shutdown();
      messageService.clearAll();
      presenceManager.clear();
      roomManager.clear();
      securityService.clear();
      _inFlight.clear();
      _flushing.clear();
      _recentReceived.clear();

      _initialized = false;
      _callbacksSetUp = false;
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
