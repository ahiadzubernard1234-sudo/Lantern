import 'package:logger/logger.dart';
import '../models/network_models.dart';
import 'package:uuid/uuid.dart';

typedef RoomCallback = void Function(RoomInfo room);

class RoomManager {
  static final RoomManager _instance = RoomManager._internal();
  final Logger _logger = Logger();

  final Map<String, RoomInfo> _rooms = {};
  final List<RoomCallback> _roomCallbacks = [];

  factory RoomManager() => _instance;
  RoomManager._internal();

  /// Create a new room
  Future<RoomInfo> createRoom({
    required String name,
    required String description,
    required String ownerId,
    List<String>? initialMembers,
  }) async {
    try {
      final roomId = const Uuid().v4();
      final now = DateTime.now();

      final members = [ownerId];
      if (initialMembers != null) {
        members.addAll(initialMembers);
      }

      final room = RoomInfo(
        roomId: roomId,
        name: name,
        description: description,
        ownerId: ownerId,
        memberIds: members,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );

      _rooms[roomId] = room;
      _logger.i('Room created: $name ($roomId)');
      _notifyRoomChange(room);

      return room;
    } catch (e) {
      _logger.e('Failed to create room: $e');
      rethrow;
    }
  }

  /// Join a room
  Future<void> joinRoom({
    required String roomId,
    required String memberId,
  }) async {
    try {
      final room = _rooms[roomId];
      if (room == null) {
        throw Exception('Room not found: $roomId');
      }

      if (room.memberIds.contains(memberId)) {
        _logger.d('Member already in room: $memberId');
        return;
      }

      final updatedMembers = [...room.memberIds, memberId];
      final updatedRoom = RoomInfo(
        roomId: room.roomId,
        name: room.name,
        description: room.description,
        ownerId: room.ownerId,
        memberIds: updatedMembers,
        createdAt: room.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      _rooms[roomId] = updatedRoom;
      _logger.i('Member joined room: $memberId in $roomId');
      _notifyRoomChange(updatedRoom);
    } catch (e) {
      _logger.e('Failed to join room: $e');
      rethrow;
    }
  }

  /// Leave a room
  Future<void> leaveRoom({
    required String roomId,
    required String memberId,
  }) async {
    try {
      final room = _rooms[roomId];
      if (room == null) return;

      if (!room.memberIds.contains(memberId)) {
        return;
      }

      final updatedMembers = room.memberIds
          .where((id) => id != memberId)
          .toList();

      // If owner leaves and no members, delete room
      if (room.ownerId == memberId && updatedMembers.isEmpty) {
        _rooms.remove(roomId);
        _logger.i('Room deleted: $roomId');
      } else if (room.ownerId == memberId && updatedMembers.isNotEmpty) {
        // Transfer ownership to first member
        final newOwner = updatedMembers.first;
        final updatedRoom = RoomInfo(
          roomId: room.roomId,
          name: room.name,
          description: room.description,
          ownerId: newOwner,
          memberIds: updatedMembers,
          createdAt: room.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        _rooms[roomId] = updatedRoom;
        _notifyRoomChange(updatedRoom);
        _logger.i('Ownership transferred to $newOwner');
      } else {
        final updatedRoom = RoomInfo(
          roomId: room.roomId,
          name: room.name,
          description: room.description,
          ownerId: room.ownerId,
          memberIds: updatedMembers,
          createdAt: room.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        _rooms[roomId] = updatedRoom;
        _notifyRoomChange(updatedRoom);
        _logger.i('Member left room: $memberId from $roomId');
      }
    } catch (e) {
      _logger.e('Failed to leave room: $e');
      rethrow;
    }
  }

  /// Remove member from room (admin only)
  Future<void> removeFromRoom({
    required String roomId,
    required String memberId,
    required String requestingUserId,
  }) async {
    try {
      final room = _rooms[roomId];
      if (room == null) return;

      // Only owner can remove
      if (room.ownerId != requestingUserId) {
        throw Exception('Only room owner can remove members');
      }

      if (!room.memberIds.contains(memberId)) {
        return;
      }

      final updatedMembers = room.memberIds
          .where((id) => id != memberId)
          .toList();

      final updatedRoom = RoomInfo(
        roomId: room.roomId,
        name: room.name,
        description: room.description,
        ownerId: room.ownerId,
        memberIds: updatedMembers,
        createdAt: room.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      _rooms[roomId] = updatedRoom;
      _logger.i('Member removed from room: $memberId from $roomId');
      _notifyRoomChange(updatedRoom);
    } catch (e) {
      _logger.e('Failed to remove member from room: $e');
      rethrow;
    }
  }

  /// Get room information
  RoomInfo? getRoom(String roomId) {
    return _rooms[roomId];
  }

  /// Get all rooms
  List<RoomInfo> getAllRooms() {
    return _rooms.values.toList();
  }

  /// Get rooms for member
  List<RoomInfo> getRoomsForMember(String memberId) {
    return _rooms.values
        .where((room) => room.memberIds.contains(memberId))
        .toList();
  }

  /// Check if member is in room
  bool isMemberInRoom(String roomId, String memberId) {
    return _rooms[roomId]?.memberIds.contains(memberId) ?? false;
  }

  /// Get room members count
  int getMembersCount(String roomId) {
    return _rooms[roomId]?.memberIds.length ?? 0;
  }

  /// Add room callback
  void addRoomCallback(RoomCallback callback) {
    _roomCallbacks.add(callback);
  }

  /// Remove room callback
  void removeRoomCallback(RoomCallback callback) {
    _roomCallbacks.remove(callback);
  }

  /// Notify room changes
  void _notifyRoomChange(RoomInfo room) {
    for (final callback in _roomCallbacks) {
      try {
        callback(room);
      } catch (e) {
        _logger.e('Error in room callback: $e');
      }
    }
  }

  /// Clear all rooms
  void clear() {
    _rooms.clear();
    _logger.d('All rooms cleared');
  }

  /// Get statistics
  Map<String, dynamic> getStats() {
    int totalMembers = 0;
    for (final room in _rooms.values) {
      totalMembers += room.memberIds.length;
    }

    return {
      'totalRooms': _rooms.length,
      'totalMembers': totalMembers,
      'avgMembersPerRoom': _rooms.isNotEmpty ? totalMembers / _rooms.length : 0,
    };
  }
}
