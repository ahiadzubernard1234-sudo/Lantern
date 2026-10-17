import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:network_info_plus/network_info_plus.dart';

typedef NetworkStatusCallback = void Function(NetworkStatus status);

class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  final Logger _logger = Logger();

  final List<NetworkStatusCallback> _callbacks = [];
  late Timer _checkTimer;

  NetworkStatus _currentStatus = NetworkStatus.unknown;
  String? _currentLocalIp;
  String? _currentSubnetMask;
  String? _currentBroadcastAddress;

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

      // Periodic checks every 10 seconds
      _checkTimer = Timer.periodic(
        const Duration(seconds: 10),
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

  /// Check current network status
  Future<void> _checkNetworkStatus() async {
    try {
      final newIpAddress = await _getLocalIpAddress();
      final newMask = newIpAddress == null ? null : await _getSubnetMask();

      // LANtern is local-first: internet access is not required.
      final newStatus = newIpAddress != null
          ? NetworkStatus.connected
          : NetworkStatus.offline;

      // IP, mask or status changed
      if (newIpAddress != _currentLocalIp ||
          newMask != _currentSubnetMask ||
          newStatus != _currentStatus) {
        _currentStatus = newStatus;
        _currentLocalIp = newIpAddress;
        _currentSubnetMask = newMask;
        _currentBroadcastAddress =
            _calculateBroadcastAddress(newIpAddress, newMask);

        _logger.d('Network status changed: $newStatus (IP: $newIpAddress, '
            'mask: $newMask, broadcast: $_currentBroadcastAddress)');
        _notifyStatusChange();
      }
    } catch (e) {
      _logger.e('Error checking network status: $e');
    }
  }

  /// Check internet connectivity
  Future<bool> _checkInternetConnectivity() async {
    try {
      // Try to reach Google DNS
      final result = await InternetAddress.lookup('8.8.8.8').timeout(
        const Duration(seconds: 5),
        onTimeout: () => [],
      );

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get local IP address
  Future<String?> _getLocalIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            // Skip loopback and link-local addresses
            if (!ip.startsWith('127.') && !ip.startsWith('169.254.')) {
              return ip;
            }
          }
        }
      }
    } catch (e) {
      _logger.e('Error getting local IP: $e');
    }
    return null;
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
      'subnetMask': _currentSubnetMask,
      'broadcastAddress': _currentBroadcastAddress,
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
