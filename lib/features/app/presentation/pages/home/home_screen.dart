import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lantern/core/network/v2/services/conversation_service.dart';
import 'package:lantern/features/app/presentation/pages/home/tabs/chats_tab.dart';
import 'package:lantern/features/app/presentation/pages/home/tabs/peers_tab.dart';
import 'package:lantern/features/app/presentation/pages/home/tabs/channels_tab.dart';
import 'package:lantern/features/app/presentation/pages/home/tabs/settings_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Remember names of people we meet, so their chats keep a name offline
    ConversationService().startRemembering();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ChatsTab(onFindPeople: () => setState(() => _selectedIndex = 1)),
      const PeersTab(),
      const ChannelsTab(),
      const SettingsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('LANtern'),
        elevation: 1,
      ),
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.people),
            label: 'Peers',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups),
            label: 'Channels',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
