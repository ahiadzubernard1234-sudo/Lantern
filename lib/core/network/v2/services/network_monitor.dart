import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';

typedef NetworkStatusCallback = void Function(NetworkStatus status);

class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  final Logger _logger = Logger();

  final List<NetworkStatusCallback> _callbacks = [];
  late Timer _checkTimer;

  NetworkStatus _currentStatus = NetworkStatus.unknown;
  String? _currentLocalIp;
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
      final hasInternetConnection = await _checkInternetConnectivity();
      final newIpAddress = await _getLocalIpAddress();

      final newStatus = hasInternetConnection
          ? NetworkStatus.connected
          : NetworkStatus.offline;

      // IP changed or status changed
      if (newIpAddress != _currentLocalIp || newStatus != _currentStatus) {
        _currentStatus = newStatus;
        _currentLocalIp = newIpAddress;
        _currentBroadcastAddress = _calculateBroadcastAddress(newIpAddress);

        _logger.d('Network status changed: $newStatus (IP: $newIpAddress)');
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
      for (var interface in NetworkInterface.listSync()) {
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

  /// Calculate broadcast address from IP
  String _calculateBroadcastAddress(String? ip) {
    if (ip == null || ip.isEmpty) {
      return '255.255.255.255';
    }

    try {
      final parts = ip.split('.');
      if (parts.length == 4) {
        return '${parts[0]}.${parts[1]}.${parts[2]}.255';
      }
    } catch (e) {
      _logger.w('Error calculating broadcast address: $e');
    }

    return '255.255.255.255';
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
