import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChannelsTab extends ConsumerStatefulWidget {
  const ChannelsTab({Key? key}) : super(key: key);

  @override
  ConsumerState<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends ConsumerState<ChannelsTab> {
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
        // Placeholder for channels list
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  'No channels yet',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
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
    Navigator.pop(context);
    // Implementation would go here
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Created channel: $name')),
    );
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
