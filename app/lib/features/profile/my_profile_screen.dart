import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../shared/widgets/photo_pager.dart';
import 'profile_repository.dart';

final myProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ProfileRepository().myProfile());

/// The current user's own profile preview + entry points to edit / settings.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (p) {
          final photoUrls = (p['photos'] as List? ?? [])
              .map((e) => Db.photoUrl((e as Map)['path'] as String))
              .toList();
          final bio = p['bio'] as String?;
          final interestLabels =
              (p['interest_labels'] as List? ?? []).map((e) => e as String).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myProfileProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AspectRatio(
                  aspectRatio: 0.8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: PhotoPager(urls: photoUrls),
                  ),
                ),
                const SizedBox(height: 16),
                Text('${p['display_name']}, ${p['age']}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(bio),
                ],
                if (interestLabels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: interestLabels.map((i) => Chip(label: Text(i))).toList()),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    await context.push('/edit-profile');
                    ref.invalidate(myProfileProvider);
                  },
                  label: const Text('Edit profile'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
