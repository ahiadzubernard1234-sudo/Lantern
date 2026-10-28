import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lantern/core/network/v2/models/network_models.dart';
import 'package:lantern/core/network/v2/network_coordinator.dart';
import 'package:lantern/core/network/v2/services/conversation_service.dart';
import 'package:lantern/features/chat/presentation/pages/peer_security_screen.dart';

/// One-to-one chat with a nearby peer.
class ChatScreen extends StatefulWidget {
  final PeerInfo peer;

  const ChatScreen({Key? key, required this.peer}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final NetworkServiceCoordinator _coordinator = NetworkServiceCoordinator();
  final TextEditingController _controller = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _peerOnline = false;
  bool _keyChanged = false;
  bool _verified = false;

  StreamSubscription<void>? _changesSub;
  StreamSubscription<dynamic>? _alertSub;
  Timer? _refreshTimer;

  String get _peerId => widget.peer.deviceId;

  @override
  void initState() {
    super.initState();
    _peerOnline = widget.peer.isOnline;

    if (_coordinator.isInitialized) {
      _keyChanged = _coordinator.cryptoService.hasPendingKeyChange(_peerId);
      _changesSub = _coordinator.chatChanges.listen((_) => _reload());
      _alertSub = _coordinator.trustAlerts
          .where((a) => a.deviceId == _peerId)
          .listen((_) {
        if (mounted) setState(() => _keyChanged = true);
      });
    }

    // Also refresh on a timer so a waiting message can switch to "not
    // delivered" even when nothing else happens
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshStatus();
      _reload();
    });
    _reload();
    _refreshStatus();
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    _alertSub?.cancel();
    _refreshTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!_coordinator.isInitialized) return;
    final list = await ConversationService().load(
      myId: _coordinator.deviceId,
      peerId: _peerId,
    );
    if (!mounted) return;
    setState(() => _messages = list);
  }

  Future<void> _refreshStatus() async {
    if (!_coordinator.isInitialized) return;
    final peer = _coordinator.discoveryService.getPeerByDeviceId(_peerId);
    final verified = await _coordinator.cryptoService.isVerified(_peerId);
    if (!mounted) return;
    setState(() {
      _peerOnline = peer?.isOnline ?? false;
      _verified = verified;
      _keyChanged = _coordinator.cryptoService.hasPendingKeyChange(_peerId);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!_coordinator.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network is still starting. Try again in a moment.')),
      );
      return;
    }
    _controller.clear();
    try {
      await _coordinator.sendMessage(recipientId: _peerId, content: text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
    }
    _reload();
  }

  Future<void> _retry(ChatMessage message) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trying again...')),
    );
    await _coordinator.retryMessage(message.id);
    _reload();
  }

  void _openSecurity() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeerSecurityScreen(peer: widget.peer)),
    ).then((_) => _refreshStatus());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peer.username),
            Text(
              _peerOnline ? 'Online' : 'Offline',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _peerOnline ? Colors.green : Colors.grey,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Security',
            icon: Icon(
              _verified ? Icons.verified_user : Icons.shield_outlined,
              color: _keyChanged
                  ? Colors.red
                  : (_verified ? Colors.green : null),
            ),
            onPressed: _openSecurity,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_keyChanged)
            Container(
              width: double.infinity,
              color: Colors.red.shade700,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This contact\'s security key changed. Messages are blocked until you review it.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: _openSecurity,
                    child: const Text('Review', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          if (!_peerOnline && !_keyChanged)
            Container(
              width: double.infinity,
              color: scheme.surfaceVariant,
              padding: const EdgeInsets.all(10),
              child: Text(
                '${widget.peer.username} is offline. Messages will be delivered when they are back on the network.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _Bubble(
                        message: message,
                        onRetry: message.status == ChatStatus.failed
                            ? () => _retry(message)
                            : null,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;

  const _Bubble({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.isMine;
    final time = TimeOfDay.fromDateTime(message.time).format(context);
    final failed = message.status == ChatStatus.failed;

    IconData? statusIcon;
    if (mine) {
      switch (message.status) {
        case ChatStatus.queued:
          statusIcon = Icons.schedule;
          break;
        case ChatStatus.failed:
          statusIcon = Icons.error_outline;
          break;
        case ChatStatus.sent:
          statusIcon = Icons.done;
          break;
        case ChatStatus.delivered:
          statusIcon = Icons.done_all;
          break;
      }
    }

    final fg = mine ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      decoration: BoxDecoration(
        color: mine ? scheme.primaryContainer : scheme.surfaceVariant,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(message.text, style: TextStyle(color: fg)),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(time, style: TextStyle(fontSize: 11, color: fg.withOpacity(0.7))),
              if (statusIcon != null) ...[
                const SizedBox(width: 4),
                Icon(
                  statusIcon,
                  size: 14,
                  color: failed ? Colors.red.shade700 : fg.withOpacity(0.7),
                ),
              ],
            ],
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Not delivered yet. Tap to retry.',
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            ),
        ],
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: onRetry == null ? bubble : GestureDetector(onTap: onRetry, child: bubble),
    );
  }
}
