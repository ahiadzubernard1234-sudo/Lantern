import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/network_models.dart';
import '../network_coordinator.dart';
import '../services/network_monitor.dart';

/// Network coordinator singleton provider
final networkCoordinatorProvider =
    Provider<NetworkServiceCoordinator>((ref) {
  return NetworkServiceCoordinator();
});

/// Discovered peers provider
final discoveredPeersProvider = StreamProvider<List<PeerInfo>>((ref) async* {
  final coordinator = ref.watch(networkCoordinatorProvider);
  while (true) {
    yield coordinator.discoveryService.getAllPeers();
    await Future.delayed(const Duration(seconds: 1));
  }
});

/// Online peers provider
final onlinePeersProvider = Provider<List<PeerInfo>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.discoveryService.getAllPeers()
      .where((p) => p.isOnline)
      .toList();
});

/// Peer count provider
final peerCountProvider = Provider<int>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.discoveryService.peerCount;
});

/// Online peer count provider
final onlinePeerCountProvider = Provider<int>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.discoveryService.onlinePeerCount;
});

/// Connected devices provider
final connectedDevicesProvider = Provider<List<String>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.connectionManager.getConnectedDevices();
});

/// Messages provider
final messagesProvider = StreamProvider<Map<String, List<NetworkMessage>>>((ref) async* {
  final coordinator = ref.watch(networkCoordinatorProvider);

  yield coordinator.messageService.getAllConversations();

  while (true) {
    await Future.delayed(const Duration(seconds: 2));
    yield coordinator.messageService.getAllConversations();
  }
});

/// Presence info provider
final presenceInfoProvider =
    Provider.family<bool?, String>((ref, deviceId) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.presenceManager.isOnline(deviceId);
});

/// Rooms provider
final roomsProvider = Provider<List<RoomInfo>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.roomManager.getAllRooms();
});

/// User's rooms provider
final userRoomsProvider = Provider<List<RoomInfo>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.roomManager.getRoomsForMember(coordinator.deviceId);
});

/// Room members provider
final roomMembersProvider =
    Provider.family<int, String>((ref, roomId) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.roomManager.getMembersCount(roomId);
});

/// File transfers provider
final fileTransfersProvider = Provider<List<FileTransferSession>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.fileTransferService.getAllTransfers();
});

/// Network status provider
final networkStatusProvider = StreamProvider<NetworkStatus>((ref) async* {
  final coordinator = ref.watch(networkCoordinatorProvider);
  while (true) {
    yield coordinator.networkMonitor.getStatus();
    await Future.delayed(const Duration(seconds: 1));
  }
});

/// Local IP provider
final localIpProvider = Provider<String?>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.networkMonitor.getLocalIp();
});

/// Broadcast address provider
final broadcastAddressProvider = Provider<String?>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.networkMonitor.getBroadcastAddress();
});

/// Diagnostics provider
final diagnosticsProvider = Provider<Map<String, dynamic>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.getDiagnostics();
});

/// Network initialized provider
final networkInitializedProvider = Provider<bool>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.isInitialized;
});

/// Delivery stats provider
final deliveryStatsProvider = Provider<Map<String, dynamic>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.deliveryManager.getStats();
});

/// Presence stats provider
final presenceStatsProvider = Provider<Map<String, int>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.presenceManager.getStats();
});

/// File transfer stats provider
final fileTransferStatsProvider = Provider<Map<String, dynamic>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.fileTransferService.getStats();
});

/// Message count provider
final messageCountProvider = Provider.family<int, String>((ref, peerId) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return coordinator.messageService.getMessageCount(peerId);
});

// State notifiers for actions

final sendMessageProvider =
    StateNotifierProvider<SendMessageNotifier, AsyncValue<void>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return SendMessageNotifier(coordinator);
});

class SendMessageNotifier extends StateNotifier<AsyncValue<void>> {
  final NetworkServiceCoordinator _coordinator;

  SendMessageNotifier(this._coordinator) : super(const AsyncValue.data(null));

  Future<void> sendMessage({
    required String recipientId,
    required String content,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _coordinator.sendMessage(
        recipientId: recipientId,
        content: content,
      );
    });
  }
}

// Room actions

final roomActionsProvider =
    StateNotifierProvider<RoomActionsNotifier, AsyncValue<void>>((ref) {
  final coordinator = ref.watch(networkCoordinatorProvider);
  return RoomActionsNotifier(coordinator);
});

class RoomActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final NetworkServiceCoordinator _coordinator;

  RoomActionsNotifier(this._coordinator) : super(const AsyncValue.data(null));

  Future<void> createRoom({
    required String name,
    required String description,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _coordinator.roomManager.createRoom(
        name: name,
        description: description,
        ownerId: _coordinator.deviceId,
      );
    });
  }

  Future<void> joinRoom({
    required String roomId,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _coordinator.roomManager.joinRoom(
        roomId: roomId,
        memberId: _coordinator.deviceId,
      );
    });
  }

  Future<void> leaveRoom({
    required String roomId,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _coordinator.roomManager.leaveRoom(
        roomId: roomId,
        memberId: _coordinator.deviceId,
      );
    });
  }
}
