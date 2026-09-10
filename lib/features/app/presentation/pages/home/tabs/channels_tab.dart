import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lantern/core/di/service_locator.dart';
import 'package:lantern/features/channels/domain/entities/channel.dart';

class ChannelsTab extends ConsumerStatefulWidget {
  const ChannelsTab({Key? key}) : super(key: key);

  @override
  ConsumerState<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends ConsumerState<ChannelsTab> {
  late Future<List<Channel>> _channelsFuture;

  @override
  void initState() {
    super.initState();
    _channelsFuture = ServiceLocator().channelRepository.getChannels();
  }

  void _refreshChannels() {
    setState(() {
      _channelsFuture = ServiceLocator().channelRepository.getChannels();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FloatingActionButton.extended(
          onPressed: _showCreateChannelDialog,
          label: const Text('Create Channel'),
          icon: const Icon(Icons.add),
        ),
        const SizedBox(height: 16),
        Text(
          'Active Channels',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Channel>>(
          future: _channelsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ));
            }
            if (snapshot.hasError) {
              return Center(child: Text('Failed to load channels: ${snapshot.error}'));
            }
            final channels = snapshot.data ?? const <Channel>[];
            if (channels.isEmpty) {
              return Center(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text('No channels yet', style: TextStyle(color: Colors.grey.shade600)),
              ));
            }
            return Column(
              children: channels.map((channel) => Card(
                child: ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(channel.name),
                  subtitle: Text(channel.description?.isNotEmpty == true ? channel.description! : '${channel.memberCount} member(s)'),
                ),
              )).toList(),
            );
          },
        ),
      ],
    );
  }

  void _showCreateChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateChannelDialog(onSubmit: _createChannel),
    );
  }

  Future<void> _createChannel(String name, String description) async {
    final profile = await ServiceLocator().profileRepository.getProfile();
    if (profile == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a profile first')));
      return;
    }
    try {
      await ServiceLocator().channelRepository.createChannel(
        name: name.trim(),
        ownerId: profile.id,
        description: description.trim().isEmpty ? null : description.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      _refreshChannels();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created channel: $name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create channel: $e')),
      );
    }
  }
}

class _CreateChannelDialog extends StatefulWidget {
  final Function(String name, String description) onSubmit;

  const _CreateChannelDialog({required this.onSubmit});

  @override
  State<_CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<_CreateChannelDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Channel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Channel Name',
              hintText: 'e.g., general',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Optional description',
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.isNotEmpty) {
              widget.onSubmit(_nameController.text, _descriptionController.text);
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
