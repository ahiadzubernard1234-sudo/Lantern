import 'package:flutter/material.dart';
import 'package:lantern/core/network/v2/models/network_models.dart';
import 'package:lantern/core/network/v2/network_coordinator.dart';

/// Lets the user compare security fingerprints with a contact and decide
/// whether to trust a changed key.
class PeerSecurityScreen extends StatefulWidget {
  final PeerInfo peer;

  const PeerSecurityScreen({Key? key, required this.peer}) : super(key: key);

  @override
  State<PeerSecurityScreen> createState() => _PeerSecurityScreenState();
}

class _PeerSecurityScreenState extends State<PeerSecurityScreen> {
  final NetworkServiceCoordinator _coordinator = NetworkServiceCoordinator();

  bool _loading = true;
  String? _peerFingerprint;
  String? _newFingerprint;
  bool _verified = false;
  bool _changed = false;

  String get _peerId => widget.peer.deviceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_coordinator.isInitialized) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final crypto = _coordinator.cryptoService;
    final fingerprint = await crypto.peerFingerprint(_peerId);
    final verified = await crypto.isVerified(_peerId);
    if (!mounted) return;
    setState(() {
      _peerFingerprint = fingerprint;
      _verified = verified;
      _changed = crypto.hasPendingKeyChange(_peerId);
      _newFingerprint = crypto.pendingFingerprint(_peerId);
      _loading = false;
    });
  }

  Future<void> _markVerified() async {
    await _coordinator.cryptoService.markVerified(_peerId);
    await _load();
  }

  Future<void> _trustNewKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trust the new key?'),
        content: Text(
          'Only continue if ${widget.peer.username} told you in person that they '
          'reinstalled the app or changed phones. If not, someone else may be '
          'pretending to be them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trust new key'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _coordinator.cryptoService.acceptKeyChange(_peerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New key trusted. Waiting messages will be sent.')),
    );
    await _load();
  }

  Widget _fingerprintCard(String title, String? value, {String? emptyText}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SelectableText(
              value ?? (emptyText ?? 'Not available yet'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: value == null ? 13 : 16,
                letterSpacing: 1,
                color: value == null ? Colors.grey : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _coordinator.isInitialized;

    return Scaffold(
      appBar: AppBar(title: Text('Security: ${widget.peer.username}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_changed)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Security key changed',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.red.shade700,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'This contact is now using a different key than before. '
                            'The connection was blocked to protect you. Compare the new '
                            'fingerprint below with theirs, in person.',
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            _newFingerprint ?? '',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 16,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _trustNewKey,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                              ),
                              child: const Text('Trust new key'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                _fingerprintCard(
                  'Your fingerprint',
                  ready ? _coordinator.localFingerprint : null,
                  emptyText: 'Network is still starting',
                ),
                _fingerprintCard(
                  '${widget.peer.username}\'s fingerprint',
                  _peerFingerprint,
                  emptyText:
                      'Not available yet. Send a message while both phones are online.',
                ),
                const SizedBox(height: 8),
                Text(
                  'To be sure nobody is pretending to be ${widget.peer.username}, '
                  'open this screen on both phones and check that each phone shows '
                  'the same two fingerprints. Their fingerprint on your phone must '
                  'match "Your fingerprint" on theirs.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (_verified)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.verified_user, color: Colors.green),
                      title: Text('Verified'),
                      subtitle: Text('You confirmed this contact\'s fingerprint.'),
                    ),
                  )
                else if (_peerFingerprint != null && !_changed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _markVerified,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('Mark as verified'),
                    ),
                  ),
              ],
            ),
    );
  }
}
