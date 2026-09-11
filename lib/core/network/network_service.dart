import 'dart:io';
import 'package:logger/logger.dart';

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  final Logger _logger = Logger();

  late ServerSocket _serverSocket;
  late RawDatagramSocket _datagramSocket;

  final Map<String, Socket> _connectedPeers = {};
  final Map<String, List<int>> _receiveBuffers = {};
  bool _isInitialized = false;

  factory NetworkService() {
    return _instance;
  }

  NetworkService._internal();

  Future<void> initialize({int tcpPort = 15555, int udpPort = 15554}) async {
    if (_isInitialized) return;

    try {
      // Initialize TCP server for receiving messages
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, tcpPort);
      _listenForIncomingConnections();
      _logger.i('TCP Server started on port $tcpPort');

      // Initialize UDP socket for broadcast
      _datagramSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _logger.i('UDP Socket initialized on port $udpPort');

      _isInitialized = true;
    } catch (e) {
      _logger.e('Failed to initialize network service: $e');
      rethrow;
    }
  }

  void _listenForIncomingConnections() {
    _serverSocket.listen(
      (Socket socket) {
        _logger.d('Incoming connection from ${socket.remoteAddress.address}:${socket.remotePort}');
        _handleIncomingConnection(socket);
      },
      onError: (error) {
        _logger.e('Server socket error: $error');
      },
      onDone: () {
        _logger.d('Server socket closed');
      },
    );
  }

  void _handleIncomingConnection(Socket socket) {
    final peerId = '${socket.remoteAddress.address}:${socket.remotePort}';

    socket.listen(
      (List<int> data) {
        final buffer = _receiveBuffers.putIfAbsent(peerId, () => <int>[]);
        buffer.addAll(data);
        while (buffer.length >= 4) {
          final length = (buffer[0] << 24) | (buffer[1] << 16) | (buffer[2] << 8) | buffer[3];
          if (length <= 0 || length > 1024 * 1024) {
            _logger.w('Invalid TCP frame from $peerId');
            socket.destroy();
            return;
          }
          if (buffer.length < length + 4) return;
          final payload = buffer.sublist(4, 4 + length);
          buffer.removeRange(0, length + 4);
          _logger.d('Received framed data from $peerId: ${payload.length} bytes');
        }
      },
      onError: (error) {
        _logger.e('Socket error for $peerId: $error');
        _connectedPeers.remove(peerId);
        _receiveBuffers.remove(peerId);
      },
      onDone: () {
        _logger.d('Connection closed from $peerId');
        _connectedPeers.remove(peerId);
        _receiveBuffers.remove(peerId);
        socket.close();
      },
    );
  }

  Future<Socket> connectToPeer(String ipAddress, int port) async {
    try {
      final socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 5));
      final peerId = '$ipAddress:$port';
      _connectedPeers[peerId] = socket;
      _logger.i('Connected to peer: $peerId');
      return socket;
    } catch (e) {
      _logger.e('Failed to connect to peer $ipAddress:$port: $e');
      rethrow;
    }
  }

  List<int> _frame(List<int> payload) {
    final length = payload.length;
    if (length > 1024 * 1024) throw ArgumentError('Message exceeds 1 MiB');
    return [
      (length >> 24) & 0xff,
      (length >> 16) & 0xff,
      (length >> 8) & 0xff,
      length & 0xff,
      ...payload,
    ];
  }

  Future<void> sendMessageToPeer(String ipAddress, int port, List<int> data) async {
    try {
      final peerId = '$ipAddress:$port';
      Socket? socket = _connectedPeers[peerId];

      if (socket == null) {
        socket = await connectToPeer(ipAddress, port);
      }

      socket.add(_frame(data));
      await socket.flush();
      _logger.d('Message sent to $peerId');
    } catch (e) {
      _logger.e('Failed to send message to $ipAddress:$port: $e');
      rethrow;
    }
  }

  Future<void> broadcastDiscoveryPacket(List<int> data, int port, {String broadcastAddress = '255.255.255.255'}) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      final address = InternetAddress(broadcastAddress);
      await _datagramSocket.send(data, address, port);
      _logger.d('Broadcast packet sent to $broadcastAddress:$port');
    } catch (e) {
      _logger.e('Failed to broadcast discovery packet: $e');
      rethrow;
    }
  }

  String? getLocalIPAddress() {
    try {
      for (final interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            if (!ip.startsWith('127.')) {
              return ip;
            }
          }
        }
      }
    } catch (e) {
      _logger.e('Failed to get local IP address: $e');
    }
    return null;
  }

  Future<void> close() async {
    try {
      for (var socket in _connectedPeers.values) {
        await socket.close();
      }
      _connectedPeers.clear();
      _receiveBuffers.clear();
      if (_isInitialized) {
        await _serverSocket.close();
        _datagramSocket.close();
      }
      _isInitialized = false;
      _logger.i('Network service closed');
    } catch (e) {
      _logger.e('Error closing network service: $e');
    }
  }

  bool get isInitialized => _isInitialized;
  Map<String, Socket> get connectedPeers => _connectedPeers;
}
