import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../chat/chat_list_screen.dart';
import '../companions/ai_discover_screen.dart';
import '../companions/ai_matches_screen.dart';
import '../companions/companions_screen.dart';
import '../profile/my_profile_screen.dart';

/// The 5-tab app shell. Each tab is a top-level route so deep links work.
/// Tabs: Discover · Likes · Companions (AI) · Chats · Profile.
class HomeShell extends StatelessWidget {
  final int tab;
  const HomeShell({super.key, required this.tab});

  static const _routes = ['/discover', '/likes', '/companions', '/chats', '/me'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: const [
          AiDiscoverScreen(),
          AiMatchesScreen(),
          CompanionsScreen(),
          ChatListScreen(),
          MyProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          if (i != tab) context.go(_routes[i]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Matches'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Companions'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
