import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'network_service.dart';

class PeerInfo {
  final String id;
  final String username;
  final String ipAddress;
  final int port;
  final String deviceId;
  final String deviceName;
  final String? avatarPath;
  final DateTime lastSeen;
  bool isOnline;

  PeerInfo({
    required this.id,
    required this.username,
    required this.ipAddress,
    required this.port,
    required this.deviceId,
    required this.deviceName,
    this.avatarPath,
    required this.lastSeen,
    this.isOnline = true,
  });

  factory PeerInfo.fromJson(Map<String, dynamic> json) {
    return PeerInfo(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      ipAddress: json['ipAddress'] ?? '',
      port: json['port'] ?? 15555,
      deviceId: json['deviceId'] ?? '',
      deviceName: json['deviceName'] ?? '',
      avatarPath: json['avatarPath'],
      lastSeen: DateTime.tryParse(json['lastSeen'] ?? '') ?? DateTime.now(),
      isOnline: json['isOnline'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'ipAddress': ipAddress,
    'port': port,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'avatarPath': avatarPath,
    'lastSeen': lastSeen.toIso8601String(),
    'isOnline': isOnline,
  };
}

class PeerDiscoveryService {
  static final PeerDiscoveryService _instance = PeerDiscoveryService._internal(NetworkService());
  final NetworkService _networkService;
  final Logger _logger = Logger();

  final Map<String, PeerInfo> _discoveredPeers = {};
  final List<Function(List<PeerInfo>)> _listeners = [];

  late RawDatagramSocket _discoverySocket;
  Timer? _discoveryBroadcastTimer;
  Timer? _peerTimeoutTimer;
  bool _isDiscovering = false;

  static const int DISCOVERY_PORT = 15554;
  static const int PEER_TIMEOUT_SECONDS = 30;
  static const int DISCOVERY_INTERVAL_SECONDS = 5;

  factory PeerDiscoveryService(NetworkService networkService) {
    return _instance;
  }

  PeerDiscoveryService._internal(this._networkService);

  Future<void> startDiscovery(String username, String deviceId, String deviceName) async {
    if (_isDiscovering) return;

    try {
      _isDiscovering = true;

      // Initialize UDP socket for discovery
      _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, DISCOVERY_PORT);
      _logger.i('Discovery socket bound to port $DISCOVERY_PORT');

      // Listen for incoming discovery packets
      _discoverySocket.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _discoverySocket.receive();
            if (datagram != null) {
              _handleDiscoveryPacket(datagram);
            }
          }
        },
        onError: (error) {
          _logger.e('Discovery socket error: $error');
        },
      );

      // Start periodic discovery broadcasts
      _startBroadcasting(username, deviceId, deviceName);

      // Start peer timeout check
      _startPeerTimeoutCheck();

      _logger.i('Peer discovery started');
    } catch (e) {
      _logger.e('Failed to start discovery: $e');
      _isDiscovering = false;
      rethrow;
    }
  }

  void _startBroadcasting(String username, String deviceId, String deviceName) {
    _discoveryBroadcastTimer = Timer.periodic(
      const Duration(seconds: DISCOVERY_INTERVAL_SECONDS),
      (_) async {
        try {
          final localIp = await _networkService.getLocalIPAddress();
          if (localIp == null) return;

          final discoveryPacket = {
            'type': 'discovery',
            'username': username,
            'ipAddress': localIp,
            'port': 15555,
            'deviceId': deviceId,
            'deviceName': deviceName,
            'timestamp': DateTime.now().toIso8601String(),
          };

          final jsonData = jsonEncode(discoveryPacket);
          final encodedData = utf8.encode(jsonData);

          await _networkService.broadcastDiscoveryPacket(
            encodedData,
            DISCOVERY_PORT,
            broadcastAddress: '255.255.255.255',
          );
        } catch (e) {
          _logger.w('Failed to broadcast discovery packet: $e');
        }
      },
    );
  }

  void _handleDiscoveryPacket(Datagram datagram) {
    try {
      final data = utf8.decode(datagram.data);
      final json = jsonDecode(data) as Map<String, dynamic>;

      if (json['type'] == 'discovery') {
        final peerInfo = PeerInfo.fromJson(json);

        // Don't add ourselves
        if (peerInfo.deviceId.isEmpty) return;

        _discoveredPeers[peerInfo.id] = peerInfo;
        _logger.d('Peer discovered: ${peerInfo.username} at ${peerInfo.ipAddress}');
        _notifyListeners();
      }
    } catch (e) {
      _logger.w('Failed to parse discovery packet: $e');
    }
  }

  void _startPeerTimeoutCheck() {
    _peerTimeoutTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        final now = DateTime.now();
        bool peersChanged = false;

        _discoveredPeers.forEach((id, peer) {
          final timeDifference = now.difference(peer.lastSeen).inSeconds;
          if (timeDifference > PEER_TIMEOUT_SECONDS && peer.isOnline) {
            peer.isOnline = false;
            peersChanged = true;
            _logger.d('Peer ${peer.username} marked as offline');
          }
        });

        if (peersChanged) {
          _notifyListeners();
        }
      },
    );
  }

  void addListener(Function(List<PeerInfo>) callback) {
    _listeners.add(callback);
    // Immediately call with current peers
    callback(getDiscoveredPeers());
  }

  void removeListener(Function(List<PeerInfo>) callback) {
    _listeners.remove(callback);
  }

  void _notifyListeners() {
    final peers = getDiscoveredPeers();
    for (var listener in _listeners) {
      listener(peers);
    }
  }

  List<PeerInfo> getDiscoveredPeers({bool onlineOnly = false}) {
    final peers = _discoveredPeers.values.toList();
    if (onlineOnly) {
      return peers.where((p) => p.isOnline).toList();
    }
    return peers;
  }

  PeerInfo? getPeerById(String id) {
    return _discoveredPeers[id];
  }

  Future<void> stopDiscovery() async {
    try {
      _isDiscovering = false;
      _discoveryBroadcastTimer?.cancel();
      _peerTimeoutTimer?.cancel();
      await _discoverySocket.close();
      _discoveredPeers.clear();
      _logger.i('Peer discovery stopped');
    } catch (e) {
      _logger.e('Failed to stop discovery: $e');
    }
  }

  int get discoveredPeerCount => _discoveredPeers.length;
  bool get isDiscovering => _isDiscovering;
}
