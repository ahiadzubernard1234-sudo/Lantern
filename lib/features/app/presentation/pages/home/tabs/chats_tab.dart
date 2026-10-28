import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lantern/core/network/v2/models/network_models.dart';
import 'package:lantern/core/network/v2/network_coordinator.dart';
import 'package:lantern/core/network/v2/services/conversation_service.dart';
import 'package:lantern/features/chat/presentation/pages/chat_screen.dart';

/// List of all conversations, so any chat can be reopened even when the
/// other person is offline.
class ChatsTab extends StatefulWidget {
  final VoidCallback? onFindPeople;

  const ChatsTab({Key? key, this.onFindPeople}) : super(key: key);

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final NetworkServiceCoordinator _coordinator = NetworkServiceCoordinator();

  List<ConversationSummary> _items = [];
  bool _loaded = false;
  StreamSubscription<void>? _changesSub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_coordinator.isInitialized) {
      if (mounted) setState(() {});
      return;
    }
    // Subscribe once the network is ready
    _changesSub ??= _coordinator.chatChanges.listen((_) => _refresh());

    final items = await ConversationService().listConversations(_coordinator.deviceId);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loaded = true;
    });
  }

  String _formatTime(BuildContext context, DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    if (day == today) return TimeOfDay.fromDateTime(time).format(context);
    if (today.difference(day).inDays == 1) return 'Yesterday';
    return '${time.day}/${time.month}/${time.year}';
  }

  Future<void> _open(ConversationSummary item) async {
    PeerInfo? peer = _coordinator.discoveryService.getPeerByDeviceId(item.peerId);
    peer ??= await ConversationService().savedPeer(item.peerId);
    peer ??= PeerInfo(
      deviceId: item.peerId,
      username: item.peerName,
      deviceName: '',
      ipAddress: '',
      port: 15555,
      lastSeen: 0,
      isOnline: false,
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(peer: peer!)),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_coordinator.isInitialized) {
      return const Center(child: Text('Starting network...'));
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 16),
              Text(
                'No conversations yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Find someone on your network and send a message. Your chats will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (widget.onFindPeople != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onFindPeople,
                  icon: const Icon(Icons.people),
                  label: const Text('Find people'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _items[index];
        final online =
            _coordinator.discoveryService.getPeerByDeviceId(item.peerId)?.isOnline ?? false;
        final initial =
            item.peerName.isEmpty ? '?' : item.peerName[0].toUpperCase();

        return ListTile(
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(child: Text(initial)),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: online ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          title: Text(item.peerName),
          subtitle: Text(
            '${item.lastIsMine ? 'You: ' : ''}${item.lastText}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            _formatTime(context, item.time),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => _open(item),
        );
      },
    );
  }
}
