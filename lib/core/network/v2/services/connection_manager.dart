import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'network_models.dart';

typedef MessageCallback = void Function(NetworkMessage message);

class ConnectionManager {
  static final ConnectionManager _instance = ConnectionManager._internal();
  final Logger _logger = Logger();

  late ServerSocket _serverSocket;
  final Map<String, _PeerConnection> _connections = {};
  final List<MessageCallback> _messageCallbacks = [];

  bool _isInitialized = false;
  String? _localDeviceId;

  static const int SERVER_PORT = 15555;
  static const int HEARTBEAT_INTERVAL_SECONDS = 10;
  static const int CONNECTION_TIMEOUT_SECONDS = 30;

  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  /// Initialize TCP server and start listening
  Future<void> initialize({required String localDeviceId}) async {
    if (_isInitialized) return;

    try {
      _localDeviceId = localDeviceId;

      // Bind TCP server
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        SERVER_PORT,
      );

      _logger.i('TCP server listening on port $SERVER_PORT');

      // Accept incoming connections
      _serverSocket.listen(
        (Socket clientSocket) {
          _handleIncomingConnection(clientSocket);
        },
        onError: (error) {
          _logger.e('Server socket error: $error');
        },
        onDone: () {
          _logger.d('Server socket closed');
        },
      );

      _isInitialized = true;
    } catch (e) {
      _logger.e('Failed to initialize connection manager: $e');
      rethrow;
    }
  }

  /// Handle incoming TCP connection
  void _handleIncomingConnection(Socket socket) {
    final remoteAddress = '${socket.remoteAddress.address}:${socket.remotePort}';
    _logger.d('Incoming connection from $remoteAddress');

    final connection = _PeerConnection(
      socket: socket,
      remoteAddress: remoteAddress,
      isOutgoing: false,
    );

    socket.listen(
      (List<int> data) {
        try {
          final message = NetworkMessage.decode(data);
          _logger.d('Message received from $remoteAddress: ${message.type}');

          // Update connection metadata if handshake
          if (message.type == MessageType.discovery) {
            final deviceId = message.metadata?['deviceId'] as String?;
            if (deviceId != null) {
              connection.remoteDeviceId = deviceId;
              _connections[deviceId] = connection;
              _logger.d('Connection established with device: $deviceId');
            }
          }

          // Notify listeners
          _notifyMessageCallbacks(message);
        } catch (e) {
          _logger.w('Error processing incoming data: $e');
        }
      },
      onError: (error) {
        _logger.e('Socket error for $remoteAddress: $error');
        connection.remoteDeviceId?.let((id) => _connections.remove(id));
      },
      onDone: () {
        _logger.d('Connection closed from $remoteAddress');
        connection.remoteDeviceId?.let((id) => _connections.remove(id));
      },
      cancelOnError: true,
    );
  }

  /// Connect to a peer
  Future<void> connectToPeer({
    required String ipAddress,
    required int port,
    required String deviceId,
  }) async {
    try {
      // Check if already connected
      if (_connections.containsKey(deviceId)) {
        _logger.d('Already connected to device: $deviceId');
        return;
      }

      final socket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 10),
      );

      _logger.i('Connected to $ipAddress:$port ($deviceId)');

      final connection = _PeerConnection(
        socket: socket,
        remoteAddress: '$ipAddress:$port',
        isOutgoing: true,
        remoteDeviceId: deviceId,
      );

      _connections[deviceId] = connection;

      // Send handshake
      await sendMessage(
        message: NetworkMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderId: _localDeviceId ?? 'unknown',
          receiverId: deviceId,
          type: MessageType.discovery,
          content: 'handshake',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          metadata: {'deviceId': _localDeviceId},
        ),
        deviceId: deviceId,
      );

      // Listen for incoming messages
      socket.listen(
        (List<int> data) {
          try {
            final message = NetworkMessage.decode(data);
            _logger.d('Message from $deviceId: ${message.type}');
            _notifyMessageCallbacks(message);
          } catch (e) {
            _logger.w('Error decoding message from $deviceId: $e');
          }
        },
        onError: (error) {
          _logger.e('Connection error with $deviceId: $error');
          _connections.remove(deviceId);
        },
        onDone: () {
          _logger.d('Connection closed with $deviceId');
          _connections.remove(deviceId);
        },
        cancelOnError: true,
      );

      // Start heartbeat
      _startHeartbeat(deviceId);
    } catch (e) {
      _logger.e('Failed to connect to $ipAddress:$port: $e');
      _connections.remove(deviceId);
      rethrow;
    }
  }

  /// Send message to peer
  Future<void> sendMessage({
    required NetworkMessage message,
    required String deviceId,
  }) async {
    try {
      final connection = _connections[deviceId];
      if (connection == null || connection.socket.done.isCompleted) {
        _logger.w('Connection not available for device: $deviceId');
        throw Exception('No active connection to $deviceId');
      }

      connection.socket.add(message.encode());
      await connection.socket.flush();

      _logger.d('Message sent to $deviceId (${message.type})');
    } catch (e) {
      _logger.e('Failed to send message to $deviceId: $e');
      _connections.remove(deviceId);
      rethrow;
    }
  }

  /// Send heartbeat to peer
  void _startHeartbeat(String deviceId) {
    Timer.periodic(
      const Duration(seconds: HEARTBEAT_INTERVAL_SECONDS),
      (timer) async {
        if (!_connections.containsKey(deviceId)) {
          timer.cancel();
          return;
        }

        try {
          final heartbeat = NetworkMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            senderId: _localDeviceId ?? 'unknown',
            receiverId: deviceId,
            type: MessageType.heartbeat,
            content: '',
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );

          await sendMessage(message: heartbeat, deviceId: deviceId);
        } catch (e) {
          _logger.w('Heartbeat failed for $deviceId: $e');
          timer.cancel();
        }
      },
    );
  }

  /// Disconnect from peer
  Future<void> disconnectPeer(String deviceId) async {
    try {
      final connection = _connections[deviceId];
      if (connection != null) {
        await connection.socket.close();
        _connections.remove(deviceId);
        _logger.i('Disconnected from $deviceId');
      }
    } catch (e) {
      _logger.e('Error disconnecting from $deviceId: $e');
    }
  }

  /// Add message callback
  void addMessageCallback(MessageCallback callback) {
    _messageCallbacks.add(callback);
  }

  /// Remove message callback
  void removeMessageCallback(MessageCallback callback) {
    _messageCallbacks.remove(callback);
  }

  /// Notify all callbacks of received message
  void _notifyMessageCallbacks(NetworkMessage message) {
    for (final callback in _messageCallbacks) {
      try {
        callback(message);
      } catch (e) {
        _logger.e('Error in message callback: $e');
      }
    }
  }

  /// Get connected peers
  List<String> getConnectedDevices() {
    return _connections.keys.toList();
  }

  /// Check if connected to device
  bool isConnectedTo(String deviceId) {
    final connection = _connections[deviceId];
    return connection != null && !connection.socket.done.isCompleted;
  }

  /// Get connection count
  int get connectionCount => _connections.length;

  /// Shutdown connection manager
  Future<void> shutdown() async {
    try {
      // Close all peer connections
      for (final deviceId in _connections.keys.toList()) {
        await disconnectPeer(deviceId);
      }

      // Close server socket
      await _serverSocket.close();
      _isInitialized = false;
      _logger.i('Connection manager shutdown');
    } catch (e) {
      _logger.e('Error shutting down connection manager: $e');
    }
  }
}

/// Internal peer connection wrapper
class _PeerConnection {
  final Socket socket;
  final String remoteAddress;
  final bool isOutgoing;
  String? remoteDeviceId;

  _PeerConnection({
    required this.socket,
    required this.remoteAddress,
    required this.isOutgoing,
    this.remoteDeviceId,
  });
}

/// Extension for null-safe let
extension NullableExtension<T> on T? {
  void let(Function(T) block) {
    if (this != null) {
      block(this as T);
    }
  }
}
