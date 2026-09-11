import 'package:logger/logger.dart';

typedef PresenceCallback = void Function(String deviceId, bool isOnline);

class PresenceManager {
  static final PresenceManager _instance = PresenceManager._internal();
  final Logger _logger = Logger();

  final Map<String, _PresenceTracker> _trackers = {};
  final List<PresenceCallback> _callbacks = [];

  static const int HEARTBEAT_INTERVAL_SECONDS = 10;
  static const int OFFLINE_THRESHOLD_SECONDS = 30;

  factory PresenceManager() => _instance;
  PresenceManager._internal();

  /// Initialize presence tracking for peer
  void initializePeer({
    required String deviceId,
    required String username,
  }) {
    if (_trackers.containsKey(deviceId)) return;

    final tracker = _PresenceTracker(
      deviceId: deviceId,
      username: username,
      lastHeartbeat: DateTime.now(),
    );

    _trackers[deviceId] = tracker;
    _logger.d('Presence tracking started for $username ($deviceId)');
  }

  /// Record heartbeat from peer
  void recordHeartbeat(String deviceId) {
    final tracker = _trackers[deviceId];
    if (tracker != null) {
      final wasOnline = tracker.isOnline;
      tracker.lastHeartbeat = DateTime.now();
      tracker.isOnline = true;

      if (!wasOnline) {
        _logger.d('Peer came online: ${tracker.username}');
        _notifyPresenceChange(deviceId, true);
      }
    }
  }

  /// Update last seen time
  void updateLastSeen(String deviceId) {
    final tracker = _trackers[deviceId];
    if (tracker != null) {
      tracker.lastSeen = DateTime.now();
    }
  }

  /// Mark peer as offline
  void markOffline(String deviceId) {
    final tracker = _trackers[deviceId];
    if (tracker != null && tracker.isOnline) {
      tracker.isOnline = false;
      _logger.d('Peer marked offline: ${tracker.username}');
      _notifyPresenceChange(deviceId, false);
    }
  }

  /// Check and update offline peers
  void checkOfflinePeers() {
    final now = DateTime.now();

    for (final entry in _trackers.entries) {
      final deviceId = entry.key;
      final tracker = entry.value;

      if (tracker.isOnline) {
        final timeSinceHeartbeat = now.difference(tracker.lastHeartbeat).inSeconds;

        if (timeSinceHeartbeat > OFFLINE_THRESHOLD_SECONDS) {
          tracker.isOnline = false;
          _logger.d('Peer timeout: ${tracker.username} (${timeSinceHeartbeat}s)');
          _notifyPresenceChange(deviceId, false);
        }
      }
    }
  }

  /// Get presence status
  bool isOnline(String deviceId) {
    return _trackers[deviceId]?.isOnline ?? false;
  }

  /// Get all online peers
  List<String> getOnlinePeers() {
    return _trackers.entries
        .where((e) => e.value.isOnline)
        .map((e) => e.key)
        .toList();
  }

  /// Get presence info for device
  PresenceInfo? getPresenceInfo(String deviceId) {
    final tracker = _trackers[deviceId];
    if (tracker == null) return null;

    return PresenceInfo(
      deviceId: deviceId,
      username: tracker.username,
      isOnline: tracker.isOnline,
      lastHeartbeat: tracker.lastHeartbeat,
      lastSeen: tracker.lastSeen,
    );
  }

  /// Add presence callback
  void addCallback(PresenceCallback callback) {
    _callbacks.add(callback);
  }

  /// Remove presence callback
  void removeCallback(PresenceCallback callback) {
    _callbacks.remove(callback);
  }

  /// Notify presence change
  void _notifyPresenceChange(String deviceId, bool isOnline) {
    for (final callback in _callbacks) {
      try {
        callback(deviceId, isOnline);
      } catch (e) {
        _logger.e('Error in presence callback: $e');
      }
    }
  }

  /// Remove peer tracking
  void removePeer(String deviceId) {
    _trackers.remove(deviceId);
    _logger.d('Peer tracking removed: $deviceId');
  }

  /// Clear all tracking
  void clear() {
    _trackers.clear();
    _logger.d('Presence tracking cleared');
  }

  /// Get statistics
  Map<String, int> getStats() {
    return {
      'total': _trackers.length,
      'online': _trackers.values.where((t) => t.isOnline).length,
      'offline': _trackers.values.where((t) => !t.isOnline).length,
    };
  }
}

/// Presence information for a peer
class PresenceInfo {
  final String deviceId;
  final String username;
  final bool isOnline;
  final DateTime lastHeartbeat;
  final DateTime lastSeen;

  PresenceInfo({
    required this.deviceId,
    required this.username,
    required this.isOnline,
    required this.lastHeartbeat,
    required this.lastSeen,
  });
}

/// Internal presence tracker
class _PresenceTracker {
  final String deviceId;
  final String username;

  bool isOnline;
  DateTime lastHeartbeat;
  DateTime lastSeen;

  _PresenceTracker({
    required this.deviceId,
    required this.username,
    required this.lastHeartbeat,
  }) : lastSeen = DateTime.now(),
       isOnline = true;
}
