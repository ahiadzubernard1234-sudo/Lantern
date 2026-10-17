import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import '../models/network_models.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  final Logger _logger = Logger();

  late RawDatagramSocket _discoverySocket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  late Timer _broadcastTimer;
  late Timer _peerTimeoutTimer;

  final Map<String, PeerInfo> _discoveredPeers = {};
  final List<Function(List<PeerInfo>)> _listeners = [];

  bool _isRunning = false;
  String? _currentDeviceId;
  String? _currentUsername;
  String? _currentDeviceName;
  String? _currentIpAddress;
  String? Function()? _broadcastProvider;

  static const int DISCOVERY_PORT = 15554;
  static const int BROADCAST_INTERVAL_SECONDS = 5;
  static const int PEER_TIMEOUT_SECONDS = 30;

  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  /// Start peer discovery service.
  ///
  /// [broadcastAddressProvider] returns the subnet-aware broadcast address
  /// (from the network monitor). Without it a /24 network is assumed.
  Future<void> startDiscovery({
    required String deviceId,
    required String username,
    required String deviceName,
    required String ipAddress,
    String? Function()? broadcastAddressProvider,
  }) async {
    if (_isRunning) return;

    try {
      _currentDeviceId = deviceId;
      _currentUsername = username;
      _currentDeviceName = deviceName;
      _currentIpAddress = ipAddress;
      _broadcastProvider = broadcastAddressProvider;

      // Bind UDP socket for receiving discovery packets
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        DISCOVERY_PORT,
      );
      // Required to send to broadcast addresses
      _discoverySocket.broadcastEnabled = true;

      _logger.i('Discovery socket bound to port $DISCOVERY_PORT');

      // Listen for incoming discovery packets
      _socketSubscription = _discoverySocket.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            try {
              final datagram = _discoverySocket.receive();
              if (datagram != null) {
                _handleDiscoveryPacket(datagram);
              }
            } catch (e) {
              _logger.w('Error handling discovery packet: $e');
            }
          }
        },
        onError: (error) {
          _logger.e('Discovery socket error: $error');
        },
      );

      _isRunning = true;

      // Send first discovery packet immediately
      await _sendDiscoveryPacket();

      // Start periodic broadcasting
      _broadcastTimer = Timer.periodic(
        const Duration(seconds: BROADCAST_INTERVAL_SECONDS),
        (_) async {
          try {
            await _sendDiscoveryPacket();
          } catch (e) {
            _logger.w('Error sending discovery packet: $e');
          }
        },
      );

      // Start peer timeout check
      _peerTimeoutTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _removeStalePeers(),
      );

      _logger.i('Discovery service started');
    } catch (e) {
      _logger.e('Failed to start discovery: $e');
      rethrow;
    }
  }

  /// Send discovery packet to every broadcast target
  Future<void> _sendDiscoveryPacket() async {
    try {
      if (!_isRunning || _currentDeviceId == null) return;

      final packet = NetworkMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: _currentDeviceId!,
        receiverId: 'broadcast',
        type: MessageType.discovery,
        content: '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        metadata: {
          'deviceId': _currentDeviceId,
          'username': _currentUsername,
          'deviceName': _currentDeviceName,
          'ipAddress': _currentIpAddress,
          'port': 15555,
        },
      );

      final encoded = packet.encode();
      for (final target in _getBroadcastTargets()) {
        try {
          _discoverySocket.send(
            encoded,
            InternetAddress(target),
            DISCOVERY_PORT,
          );
          _logger.d('Discovery packet sent to $target:$DISCOVERY_PORT');
        } catch (e) {
          _logger.w('Failed to send discovery packet to $target: $e');
        }
      }
    } catch (e) {
      _logger.w('Failed to send discovery packet: $e');
    }
  }

  /// Broadcast targets: subnet-aware address, /24 guess, then global broadcast
  List<String> _getBroadcastTargets() {
    final targets = <String>[];

    try {
      final provided = _broadcastProvider?.call();
      if (provided != null && provided.isNotEmpty) targets.add(provided);
    } catch (e) {
      _logger.w('Broadcast provider failed: $e');
    }

    final ip = _currentIpAddress;
    if (ip != null && ip.isNotEmpty) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }

    targets.add('255.255.255.255');
    return targets.toSet().toList();
  }

  /// Handle incoming discovery packet
  void _handleDiscoveryPacket(Datagram datagram) {
    try {
      final packet = NetworkMessage.decode(datagram.data);

      if (packet.type != MessageType.discovery) return;

      final metadata = packet.metadata;
      if (metadata == null) return;

      final deviceId = metadata['deviceId'];
      if (deviceId is! String || deviceId.isEmpty) return;

      // Ignore own discovery packets
      if (deviceId == _currentDeviceId) {
        return;
      }

      // Use the real source address, not the one the packet claims.
      // (Identity is verified later by the encrypted handshake.)
      final peer = PeerInfo(
        deviceId: deviceId,
        username: metadata['username'] is String ? metadata['username'] as String : 'Unknown',
        deviceName: metadata['deviceName'] is String ? metadata['deviceName'] as String : 'Unknown Device',
        ipAddress: datagram.address.address,
        port: metadata['port'] is int ? metadata['port'] as int : 15555,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        isOnline: true,
      );

      final previousPeer = _discoveredPeers[deviceId];
      _discoveredPeers[deviceId] = peer;

      if (previousPeer == null) {
        _logger.d('New peer discovered: ${peer.username} (${peer.ipAddress})');
      } else {
        _logger.d('Peer updated: ${peer.username}');
      }

      _notifyListeners();
    } catch (e) {
      _logger.w('Error parsing discovery packet: $e');
    }
  }

  /// Remove peers not seen recently
  void _removeStalePeers() {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final staleDevices = <String>[];

      _discoveredPeers.forEach((deviceId, peer) {
        final age = now - peer.lastSeen;
        final ageSeconds = age ~/ 1000;

        if (ageSeconds > PEER_TIMEOUT_SECONDS && peer.isOnline) {
          staleDevices.add(deviceId);
          _logger.d('Peer timeout: ${peer.username} (${ageSeconds}s)');
        }
      });

      if (staleDevices.isNotEmpty) {
        for (final deviceId in staleDevices) {
          final peer = _discoveredPeers[deviceId];
          if (peer != null) {
            _discoveredPeers[deviceId] = peer.copyWith(isOnline: false);
          }
        }
        _notifyListeners();
      }
    } catch (e) {
      _logger.e('Error removing stale peers: $e');
    }
  }

  /// Add listener for peer updates
  void addListener(Function(List<PeerInfo>) callback) {
    _listeners.add(callback);
    // Notify immediately with current peers
    callback(_getOnlinePeers());
  }

  /// Remove listener
  void removeListener(Function(List<PeerInfo>) callback) {
    _listeners.remove(callback);
  }

  /// Notify all listeners of peer changes
  void _notifyListeners() {
    final peers = _getOnlinePeers();
    for (final listener in _listeners) {
      try {
        listener(peers);
      } catch (e) {
        _logger.e('Error notifying listener: $e');
      }
    }
  }

  /// Get all online peers
  List<PeerInfo> _getOnlinePeers() {
    return _discoveredPeers.values
        .where((p) => p.isOnline)
        .toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  /// Get all peers (online and offline)
  List<PeerInfo> getAllPeers() {
    return _discoveredPeers.values.toList()
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) {
          return a.isOnline ? -1 : 1;
        }
        return b.lastSeen.compareTo(a.lastSeen);
      });
  }

  /// Get peer by device ID
  PeerInfo? getPeerByDeviceId(String deviceId) {
    return _discoveredPeers[deviceId];
  }

  /// Stop discovery service
  Future<void> stopDiscovery() async {
    try {
      if (_isRunning) {
        _broadcastTimer.cancel();
        _peerTimeoutTimer.cancel();
        await _socketSubscription?.cancel();
        _socketSubscription = null;
        _discoverySocket.close();
        _isRunning = false;
      }
      _discoveredPeers.clear();
      _listeners.clear();
      _logger.i('Discovery service stopped');
    } catch (e) {
      _logger.e('Error stopping discovery: $e');
    }
  }

  /// Check if discovery is running
  bool get isRunning => _isRunning;

  /// Get peer count
  int get peerCount => _discoveredPeers.length;

  /// Get online peer count
  int get onlinePeerCount => _discoveredPeers.values.where((p) => p.isOnline).length;
}
