import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/demo/demo_store.dart';
import '../../core/supabase.dart';

final _settingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (AppConfig.demo) return DemoStore.instance.settings();
  final s = await Db.client.from('user_settings').select().eq('user_id', Db.uid!).maybeSingle();
  final p = await Db.client.from('profiles').select('is_discoverable').eq('id', Db.uid!).single();
  return {...?s, 'is_discoverable': p['is_discoverable']};
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _set(WidgetRef ref, String col, bool v) async {
    if (AppConfig.demo) {
      DemoStore.instance.setSetting(col, v);
    } else {
      await Db.client.from('user_settings').update({col: v}).eq('user_id', Db.uid!);
    }
    ref.invalidate(_settingsProvider);
  }

  Future<void> _setDiscoverable(WidgetRef ref, bool v) async {
    if (AppConfig.demo) {
      DemoStore.instance.setSetting('is_discoverable', v);
    } else {
      await Db.client.from('profiles').update({'is_discoverable': v}).eq('id', Db.uid!);
    }
    ref.invalidate(_settingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) {
          bool f(String k, [bool d = true]) => (s[k] as bool?) ?? d;
          return ListView(
            children: [
              const _Header('Discovery'),
              SwitchListTile(
                title: const Text('Show me on Discover'),
                subtitle: const Text('Turn off to hide your profile from others'),
                value: f('is_discoverable'),
                onChanged: (v) => _setDiscoverable(ref, v),
              ),
              SwitchListTile(
                title: const Text('Show online status'),
                value: f('show_online_status'),
                onChanged: (v) => _set(ref, 'show_online_status', v),
              ),
              SwitchListTile(
                title: const Text('Show distance'),
                value: f('show_distance'),
                onChanged: (v) => _set(ref, 'show_distance', v),
              ),
              const _Header('Notifications'),
              SwitchListTile(
                title: const Text('New messages'),
                value: f('notify_messages'),
                onChanged: (v) => _set(ref, 'notify_messages', v),
              ),
              SwitchListTile(
                title: const Text('New matches'),
                value: f('notify_matches'),
                onChanged: (v) => _set(ref, 'notify_matches', v),
              ),
              SwitchListTile(
                title: const Text('New likes'),
                value: f('notify_likes'),
                onChanged: (v) => _set(ref, 'notify_likes', v),
              ),
              const _Header('Account'),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log out'),
                enabled: !AppConfig.demo,
                subtitle: AppConfig.demo ? const Text('Disabled in demo build') : null,
                onTap: AppConfig.demo ? null : () => Db.auth.signOut(),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete account', style: TextStyle(color: Colors.red)),
                enabled: !AppConfig.demo,
                subtitle: AppConfig.demo ? const Text('Disabled in demo build') : null,
                onTap: AppConfig.demo ? null : () => _confirmDelete(context),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This permanently removes your profile, photos, matches and messages. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Deleting the profile row cascades to all app data. Full auth-user deletion
    // is completed by the `delete-account` Edge Function (service role).
    await Db.client.functions.invoke('delete-account');
    await Db.auth.signOut();
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5)),
      );
}
