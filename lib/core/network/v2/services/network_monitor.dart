import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:network_info_plus/network_info_plus.dart';

typedef NetworkStatusCallback = void Function(NetworkStatus status);

class _Lan {
  final String name;
  final String ip;
  final int score;
  const _Lan(this.name, this.ip, this.score);
}

class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  static const MethodChannel _channel = MethodChannel('lantern/network');
  final Logger _logger = Logger();

  final List<NetworkStatusCallback> _callbacks = [];
  late Timer _checkTimer;

  NetworkStatus _currentStatus = NetworkStatus.unknown;
  String? _currentLocalIp;
  String? _currentSubnetMask;
  String? _currentBroadcastAddress;
  String? _lanInterface;
  bool? _wifiRadioOn;
  bool? _multicastLockHeld;

  bool _isMonitoring = false;

  factory NetworkMonitor() => _instance;
  NetworkMonitor._internal();

  /// Start network monitoring
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    try {
      _isMonitoring = true;

      // Initial check
      await _checkNetworkStatus();

      // Periodic checks every 5 seconds
      _checkTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) async {
          try {
            await _checkNetworkStatus();
          } catch (e) {
            _logger.w('Error checking network status: $e');
          }
        },
      );

      _logger.i('Network monitoring started');
    } catch (e) {
      _logger.e('Failed to start network monitoring: $e');
      _isMonitoring = false;
      rethrow;
    }
  }

  /// Ask Android whether Wi-Fi is on and whether the multicast lock is held
  Future<void> _queryNative() async {
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('getWifiInfo');
      _wifiRadioOn = info?['wifiEnabled'] as bool?;
      _multicastLockHeld = info?['multicastLockHeld'] as bool?;
    } catch (_) {
      // Not on Android, or the channel is unavailable. Leave values unknown.
    }
  }

  /// Check current network status
  Future<void> _checkNetworkStatus() async {
    try {
      await _queryNative();

      final lan = await _findLan();
      final newIp = lan?.ip;
      final newInterface = lan?.name;
      final newMask = (lan != null && _isWifiClientName(lan.name))
          ? await _getSubnetMask()
          : null;

      // LANtern is local-first: internet access is not required.
      final newStatus =
          newIp != null ? NetworkStatus.connected : NetworkStatus.offline;

      if (newIp != _currentLocalIp ||
          newInterface != _lanInterface ||
          newMask != _currentSubnetMask ||
          newStatus != _currentStatus) {
        _currentStatus = newStatus;
        _currentLocalIp = newIp;
        _lanInterface = newInterface;
        _currentSubnetMask = newMask;
        _currentBroadcastAddress = _calculateBroadcastAddress(newIp, newMask);

        _logger.i('Network changed: $statusMessage '
            '(mask: ${newMask ?? 'unknown'}, broadcast: $_currentBroadcastAddress, '
            'Wi-Fi radio: ${_wifiRadioOn ?? 'unknown'}, '
            'multicast lock: ${_multicastLockHeld ?? 'unknown'})');
        _notifyStatusChange();
      }
    } catch (e) {
      _logger.e('Error checking network status: $e');
    }
  }

  bool _isCellularName(String name) {
    const blocked = [
      'lo', 'rmnet', 'ccmni', 'pdp', 'v4-', 'clat', 'tun', 'tap', 'dummy',
      'ppp', 'ifb', 'sit', 'ip6tnl', 'bond', 'p2p', 'rev_rmnet', 'r_rmnet',
    ];
    return blocked.any((b) => name == b || name.startsWith(b));
  }

  bool _isWifiClientName(String name) =>
      name.startsWith('wlan') || name.startsWith('wifi') || name == 'wifi';

  bool _isHotspotName(String name) =>
      name.startsWith('ap') || name.startsWith('swlan') || name.startsWith('softap');

  bool _isPrivate(String ip) {
    final p = _parseIpv4(ip);
    if (p == null) return false;
    if (p[0] == 10) return true;
    if (p[0] == 192 && p[1] == 168) return true;
    if (p[0] == 172 && p[1] >= 16 && p[1] <= 31) return true;
    return false;
  }

  /// Find the address on the local Wi-Fi or hotspot network, never mobile data.
  Future<_Lan?> _findLan() async {
    final found = <_Lan>[];

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (_isCellularName(name)) continue;

        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;

          final wifiLike = _isWifiClientName(name) || _isHotspotName(name);
          if (!wifiLike && !_isPrivate(ip)) continue;

          final score = wifiLike ? 5 : (name.startsWith('eth') ? 3 : 1);
          found.add(_Lan(iface.name, ip, score));
        }
      }
    } catch (e) {
      _logger.w('Could not list network interfaces: $e');
    }

    if (found.isEmpty) {
      // Some Android versions hide interfaces; ask the Wi-Fi service instead.
      try {
        final wifiIp = await NetworkInfo().getWifiIP();
        if (wifiIp != null && _parseIpv4(wifiIp) != null && wifiIp != '0.0.0.0') {
          found.add(_Lan('wifi', wifiIp, 4));
        }
      } catch (e) {
        _logger.w('Could not read Wi-Fi address: $e');
      }
    }

    if (found.isEmpty) return null;
    found.sort((a, b) => b.score.compareTo(a.score));
    return found.first;
  }

  /// Get the Wi-Fi subnet mask (null on hotspot host or when unavailable)
  Future<String?> _getSubnetMask() async {
    try {
      return await NetworkInfo().getWifiSubmask();
    } catch (e) {
      return null;
    }
  }

  List<int>? _parseIpv4(String? value) {
    if (value == null) return null;
    final parts = value.split('.');
    if (parts.length != 4) return null;
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      out.add(n);
    }
    return out;
  }

  /// Calculate the directed broadcast address from IP and subnet mask.
  /// Falls back to a /24 network when the mask is unknown.
  String _calculateBroadcastAddress(String? ip, [String? mask]) {
    final ipParts = _parseIpv4(ip);
    if (ipParts == null) {
      return '255.255.255.255';
    }

    var maskParts = _parseIpv4(mask);
    if (maskParts == null || maskParts.every((b) => b == 0)) {
      maskParts = [255, 255, 255, 0];
    }

    final broadcast = List<int>.generate(
      4,
      (i) => (ipParts[i] & maskParts![i]) | ((~maskParts[i]) & 0xFF),
    );
    return broadcast.join('.');
  }

  /// Plain-language description of the connection
  String get statusMessage {
    if (_currentLocalIp != null) {
      return 'Connected on ${_lanInterface ?? 'network'} ($_currentLocalIp)';
    }
    if (_wifiRadioOn == false) {
      return 'Wi-Fi is off. Turn on Wi-Fi and join the same network as your friends, or start a hotspot.';
    }
    return 'No Wi-Fi or hotspot network found. Join the same Wi-Fi as your friends, or turn on a phone hotspot.';
  }

  /// Whether the Wi-Fi radio is on (null if unknown)
  bool? get wifiRadioOn => _wifiRadioOn;

  /// Whether the Android multicast lock is held (null if unknown)
  bool? get multicastLockHeld => _multicastLockHeld;

  /// Name of the network interface in use (for example wlan0)
  String? get lanInterface => _lanInterface;

  /// Check if connected to network
  bool isConnected() => _currentStatus == NetworkStatus.connected;

  /// Get current network status
  NetworkStatus getStatus() => _currentStatus;

  /// Get local IP address
  String? getLocalIp() => _currentLocalIp;

  /// Get broadcast address
  String? getBroadcastAddress() => _currentBroadcastAddress;

  /// Add status callback
  void addStatusCallback(NetworkStatusCallback callback) {
    _callbacks.add(callback);
    // Notify immediately
    callback(_currentStatus);
  }

  /// Remove status callback
  void removeStatusCallback(NetworkStatusCallback callback) {
    _callbacks.remove(callback);
  }

  /// Notify status changes
  void _notifyStatusChange() {
    for (final callback in _callbacks) {
      try {
        callback(_currentStatus);
      } catch (e) {
        _logger.e('Error in network status callback: $e');
      }
    }
  }

  /// Stop network monitoring
  Future<void> stopMonitoring() async {
    try {
      if (_isMonitoring) {
        _checkTimer.cancel();
        _isMonitoring = false;
        _logger.i('Network monitoring stopped');
      }
    } catch (e) {
      _logger.e('Error stopping network monitoring: $e');
    }
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    return {
      'status': _currentStatus.toString(),
      'localIp': _currentLocalIp,
      'interface': _lanInterface,
      'subnetMask': _currentSubnetMask,
      'broadcastAddress': _currentBroadcastAddress,
      'wifiRadioOn': _wifiRadioOn,
      'multicastLockHeld': _multicastLockHeld,
      'isMonitoring': _isMonitoring,
    };
  }
}

/// Network status enum
enum NetworkStatus {
  unknown,
  connected,
  offline,
}
