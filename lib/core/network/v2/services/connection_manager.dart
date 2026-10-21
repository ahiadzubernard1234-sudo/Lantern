import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import '../models/network_models.dart';
import 'crypto_service.dart';

typedef MessageCallback = void Function(NetworkMessage message);

/// Called when a connected peer introduces itself (name, device, port).
typedef HandshakeCallback = void Function(
    String deviceId, String ipAddress, Map<String, dynamic> info);

/// TCP connections between peers.
///
/// Every connection starts with a signed hello (X25519 key exchange bound to
/// the device's Ed25519 identity). After that, all frames are encrypted with
/// ChaCha20-Poly1305. Messages whose sender does not match the authenticated
/// device of the connection are dropped.
class ConnectionManager {
  static final ConnectionManager _instance = ConnectionManager._internal();
  final Logger _logger = Logger();
  final CryptoService _crypto = CryptoService();

  late ServerSocket _serverSocket;
  StreamSubscription<Socket>? _serverSubscription;
  final Map<String, _PeerConnection> _connections = {};
  final Set<_PeerConnection> _open = {};
  final Map<String, Future<void>> _connecting = {};
  final Map<String, Future<String>> _connectingAddresses = {};
  final List<MessageCallback> _messageCallbacks = [];
  final List<HandshakeCallback> _handshakeCallbacks = [];
  final Map<String, Timer> _heartbeatTimers = {};

  bool _isInitialized = false;
  String? _localDeviceId;
  String? _localUsername;
  String? _localDeviceName;

  static const int SERVER_PORT = 15555;
  static const int HEARTBEAT_INTERVAL_SECONDS = 10;
  static const int CONNECTION_TIMEOUT_SECONDS = 30;
  static const int HANDSHAKE_TIMEOUT_SECONDS = 10;

  static const int _tagHello = 1;
  static const int _tagData = 2;
  static const int _maxFrameSize = 1024 * 1024;
  static const int _maxPreAuthFrameSize = 8 * 1024;

  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  /// Name and device shown to peers when we introduce ourselves.
  void setLocalProfile({required String username, required String deviceName}) {
    _localUsername = username;
    _localDeviceName = deviceName;
  }

  /// Initialize TCP server and start listening
  Future<void> initialize({required String localDeviceId}) async {
    if (_isInitialized) return;

    try {
      _localDeviceId = localDeviceId;

      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        SERVER_PORT,
      );

      _logger.i('TCP server listening on port $SERVER_PORT');

      _serverSubscription = _serverSocket.listen(
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
    _logger.i('Incoming connection from $remoteAddress');

    final connection = _PeerConnection(
      socket: socket,
      remoteAddress: remoteAddress,
      isOutgoing: false,
    );
    _attach(connection);
  }

  /// Wire up a socket: handshake timeout and data/error/done handlers.
  void _attach(_PeerConnection c) {
    _open.add(c);

    c.handshakeTimer = Timer(
      const Duration(seconds: HANDSHAKE_TIMEOUT_SECONDS),
      () {
        if (c.keys == null) {
          _logger.w('Handshake timeout with ${c.remoteAddress}');
          _removeConnection(c);
        }
      },
    );

    c.subscription = c.socket.listen(
      (List<int> data) => _onData(c, data),
      onError: (Object error) {
        _logger.e('Socket error for ${c.remoteAddress}: $error');
        _removeConnection(c);
      },
      onDone: () {
        _logger.d('Connection closed ${c.remoteAddress}');
        _removeConnection(c);
      },
      cancelOnError: true,
    );
  }

  /// Connect to a discovered peer (one attempt at a time per device)
  Future<void> connectToPeer({
    required String ipAddress,
    required int port,
    required String deviceId,
  }) {
    if (isConnectedTo(deviceId)) {
      _logger.d('Already connected to device: $deviceId');
      return Future.value();
    }
    return _connecting.putIfAbsent(
      deviceId,
      () => _connect(
        ipAddress: ipAddress,
        port: port,
        expectedDeviceId: deviceId,
      ).then((_) {}).whenComplete(() => _connecting.remove(deviceId)),
    );
  }

  /// Connect to a phone by its IP address when its identity is not known yet.
  /// Returns the verified device ID of the other phone.
  Future<String> connectToAddress({
    required String ipAddress,
    required int port,
  }) {
    final key = '$ipAddress:$port';
    return _connectingAddresses.putIfAbsent(
      key,
      () => _connect(ipAddress: ipAddress, port: port)
          .whenComplete(() => _connectingAddresses.remove(key)),
    );
  }

  Future<String> _connect({
    required String ipAddress,
    required int port,
    String? expectedDeviceId,
  }) async {
    _logger.i('Connecting to $ipAddress:$port ...');

    final Socket socket;
    try {
      socket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 8),
      );
    } catch (e) {
      _logger.w('TCP connection to $ipAddress:$port failed: $e');
      rethrow;
    }

    _logger.i('TCP connected to $ipAddress:$port, starting secure handshake');

    final connection = _PeerConnection(
      socket: socket,
      remoteAddress: '$ipAddress:$port',
      isOutgoing: true,
      expectedDeviceId: expectedDeviceId,
    );
    _attach(connection);

    try {
      await (connection.helloSending ??= _sendHello(connection));
      final ok = await connection.ready.future.timeout(
        const Duration(seconds: HANDSHAKE_TIMEOUT_SECONDS),
        onTimeout: () => false,
      );
      if (!ok) {
        throw Exception(
            'Secure handshake with $ipAddress failed (different app version, or the security key changed)');
      }

      final remoteId = connection.remoteDeviceId!;
      _logger.i('Secure session established with $remoteId at $ipAddress');

      // Introduce ourselves (name, device, port)
      await _sendHandshake(connection);
      _startHeartbeat(remoteId);
      return remoteId;
    } catch (e) {
      _removeConnection(connection);
      _logger.w('Connection to $ipAddress:$port failed: $e');
      rethrow;
    }
  }

  /// Send our signed hello
  Future<void> _sendHello(_PeerConnection c) async {
    final hello = await _crypto.createHello(_localDeviceId ?? 'unknown');
    c.localHello = hello;
    final payload = [_tagHello, ...utf8.encode(jsonEncode(hello.json))];
    c.socket.add(_frame(payload));
    await c.socket.flush();
  }

  /// Tell the other phone who we are (once per connection)
  Future<void> _sendHandshake(_PeerConnection c) async {
    if (c.handshakeSent) return;
    c.handshakeSent = true;

    final message = NetworkMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: _localDeviceId ?? 'unknown',
      receiverId: c.remoteDeviceId ?? 'unknown',
      type: MessageType.discovery,
      content: 'handshake',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      metadata: {
        'deviceId': _localDeviceId,
        'username': _localUsername ?? 'Unknown',
        'deviceName': _localDeviceName ?? 'Unknown Device',
        'port': SERVER_PORT,
      },
    );
    await _sendOn(c, message);
  }

  Future<void> _sendOn(_PeerConnection c, NetworkMessage message) async {
    final keys = c.keys;
    if (keys == null) throw Exception('Secure session is not ready');
    final cipher = await _crypto.encrypt(keys.send, message.encode());
    c.socket.add(_frame([_tagData, ...cipher]));
    await c.socket.flush();
  }

  /// Send message to peer (encrypted)
  Future<void> sendMessage({
    required NetworkMessage message,
    required String deviceId,
  }) async {
    try {
      final connection = _connections[deviceId];
      if (connection == null || connection.keys == null) {
        _logger.w('Connection not available for device: $deviceId');
        throw Exception('No active connection to $deviceId');
      }

      await _sendOn(connection, message);
      _logger.d('Message sent to $deviceId (${message.type})');
    } catch (e) {
      _logger.e('Failed to send message to $deviceId: $e');
      _connections.remove(deviceId);
      rethrow;
    }
  }

  List<int> _frame(List<int> payload) {
    if (payload.length > _maxFrameSize) {
      throw ArgumentError('Message exceeds $_maxFrameSize bytes');
    }
    return [
      (payload.length >> 24) & 0xff,
      (payload.length >> 16) & 0xff,
      (payload.length >> 8) & 0xff,
      payload.length & 0xff,
      ...payload,
    ];
  }

  /// Collect bytes and split them into length-prefixed frames
  void _onData(_PeerConnection c, List<int> data) {
    c.buffer.addAll(data);
    while (c.buffer.length >= 4) {
      final length =
          (c.buffer[0] << 24) | (c.buffer[1] << 16) | (c.buffer[2] << 8) | c.buffer[3];
      final limit = c.keys == null ? _maxPreAuthFrameSize : _maxFrameSize;
      if (length <= 0 || length > limit) {
        _logger.w('Invalid frame length from ${c.remoteAddress}: $length');
        _removeConnection(c);
        return;
      }
      if (c.buffer.length < length + 4) return;
      final payload = c.buffer.sublist(4, 4 + length);
      c.buffer.removeRange(0, 4 + length);

      // Process frames one at a time, in order
      c.inbox = c.inbox
          .then((_) => _processFrame(c, payload))
          .catchError((Object e) {
        _logger.w('Error processing frame from ${c.remoteAddress}: $e');
      });
    }
  }

  Future<void> _processFrame(_PeerConnection c, List<int> payload) async {
    if (payload.isEmpty) return;
    final tag = payload[0];
    final body = payload.sublist(1);

    if (tag == _tagHello) {
      await _onHello(c, body);
      return;
    }

    if (tag != _tagData) {
      _logger.w('Unknown frame tag $tag from ${c.remoteAddress}');
      return;
    }

    final keys = c.keys;
    if (keys == null) {
      _logger.w('Data before handshake from ${c.remoteAddress}, closing');
      _removeConnection(c);
      return;
    }

    final List<int> plain;
    try {
      plain = await _crypto.decrypt(keys.receive, body);
    } catch (e) {
      _logger.w('Decryption failed from ${c.remoteAddress}, closing: $e');
      _removeConnection(c);
      return;
    }

    final message = NetworkMessage.decode(plain);

    // The sender must be the device this connection authenticated as.
    if (message.senderId != c.remoteDeviceId) {
      _logger.w('Dropped message with spoofed sender ${message.senderId} '
          'on connection authenticated as ${c.remoteDeviceId}');
      return;
    }

    // Peer introductions are handled here, not passed on as chat traffic
    if (message.type == MessageType.discovery && message.content == 'handshake') {
      await _onHandshake(c, message);
      return;
    }

    _logger.d('Message received from ${c.remoteDeviceId}: ${message.type}');
    _notifyMessageCallbacks(message);
  }

  /// The other phone told us who it is
  Future<void> _onHandshake(_PeerConnection c, NetworkMessage message) async {
    final info = Map<String, dynamic>.from(message.metadata ?? {});
    final deviceId = c.remoteDeviceId;
    if (deviceId == null) return;
    final ip = c.socket.remoteAddress.address;

    _logger.i('Introduction from ${info['username'] ?? deviceId} at $ip');

    for (final callback in List<HandshakeCallback>.of(_handshakeCallbacks)) {
      try {
        callback(deviceId, ip, info);
      } catch (e) {
        _logger.e('Error in handshake callback: $e');
      }
    }

    // Answer with our own introduction and keep the link alive
    if (!c.handshakeSent) {
      try {
        await _sendHandshake(c);
      } catch (e) {
        _logger.w('Could not send introduction to $deviceId: $e');
      }
    }
    if (!c.isOutgoing) _startHeartbeat(deviceId);
  }

  /// Verify the peer's hello, pin its key, and derive session keys
  Future<void> _onHello(_PeerConnection c, List<int> body) async {
    if (c.keys != null) return; // ignore repeated hellos

    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    } catch (_) {
      _logger.w('Malformed hello from ${c.remoteAddress}');
      _removeConnection(c);
      return;
    }

    final hello = await _crypto.verifyHello(json);
    if (hello == null ||
        hello.deviceId == _localDeviceId ||
        (c.expectedDeviceId != null && hello.deviceId != c.expectedDeviceId)) {
      _logger.w('Rejected hello from ${c.remoteAddress}');
      _removeConnection(c);
      return;
    }

    final trust = await _crypto.checkTrust(hello.deviceId, hello.identityKey);
    if (trust == TrustState.changed) {
      _removeConnection(c);
      return;
    }

    // Incoming side answers with its own hello
    await (c.helloSending ??= _sendHello(c));
    final local = c.localHello!;
    if (local.ephemeralKey == hello.ephemeralKey) {
      _logger.w('Rejected reflected hello from ${c.remoteAddress}');
      _removeConnection(c);
      return;
    }

    c.keys = await _crypto.deriveSession(
      myEphemeral: local.ephemeral,
      myEphemeralKey: local.ephemeralKey,
      theirEphemeralKey: hello.ephemeralKey,
    );
    c.remoteDeviceId = hello.deviceId;
    c.handshakeTimer?.cancel();
    _connections[hello.deviceId] = c;
    if (!c.ready.isCompleted) c.ready.complete(true);
    _logger.i('Secure session with ${hello.deviceId}');
  }

  void _removeConnection(_PeerConnection connection) {
    _open.remove(connection);
    final id = connection.remoteDeviceId;
    if (id != null && identical(_connections[id], connection)) {
      _connections.remove(id);
      _heartbeatTimers.remove(id)?.cancel();
      _logger.i('Connection to $id closed');
    }
    connection.handshakeTimer?.cancel();
    connection.subscription?.cancel();
    if (!connection.ready.isCompleted) connection.ready.complete(false);
    connection.socket.destroy();
  }

  /// Send heartbeat to peer
  void _startHeartbeat(String deviceId) {
    _heartbeatTimers[deviceId]?.cancel();
    _heartbeatTimers[deviceId] = Timer.periodic(
      const Duration(seconds: HEARTBEAT_INTERVAL_SECONDS),
      (timer) async {
        if (!_connections.containsKey(deviceId)) {
          timer.cancel();
          _heartbeatTimers.remove(deviceId);
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
          _heartbeatTimers.remove(deviceId);
        }
      },
    );
  }

  /// Disconnect from peer
  Future<void> disconnectPeer(String deviceId) async {
    try {
      final connection = _connections[deviceId];
      if (connection != null) {
        _heartbeatTimers.remove(deviceId)?.cancel();
        _removeConnection(connection);
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

  /// Be told when a connected peer introduces itself
  void addHandshakeCallback(HandshakeCallback callback) {
    _handshakeCallbacks.add(callback);
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

  /// Get connected peers (secure sessions only)
  List<String> getConnectedDevices() {
    return _connections.keys.toList();
  }

  /// Check if connected to device
  bool isConnectedTo(String deviceId) {
    final connection = _connections[deviceId];
    return connection != null && connection.keys != null;
  }

  /// Get connection count
  int get connectionCount => _connections.length;

  /// Shutdown connection manager
  Future<void> shutdown() async {
    try {
      for (final timer in _heartbeatTimers.values) {
        timer.cancel();
      }
      _heartbeatTimers.clear();
      await _serverSubscription?.cancel();
      _serverSubscription = null;
      for (final connection in _open.toList()) {
        _removeConnection(connection);
      }
      _connections.clear();
      _connecting.clear();
      _connectingAddresses.clear();
      if (_isInitialized) await _serverSocket.close();
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
  final String? expectedDeviceId;
  String? remoteDeviceId;
  bool handshakeSent = false;

  final List<int> buffer = <int>[];
  final Completer<bool> ready = Completer<bool>();
  Future<void> inbox = Future<void>.value();
  Future<void>? helloSending;
  LocalHello? localHello;
  SessionKeys? keys;
  StreamSubscription<List<int>>? subscription;
  Timer? handshakeTimer;

  _PeerConnection({
    required this.socket,
    required this.remoteAddress,
    required this.isOutgoing,
    this.expectedDeviceId,
  });
}
