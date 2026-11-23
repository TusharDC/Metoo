import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/profile_card.dart';
import '../../shared/widgets/app_image.dart';
import '../discover/discover_repository.dart';

final _likesProvider =
    FutureProvider.autoDispose<List<ProfileCard>>((ref) => DiscoverRepository().incomingLikes());

/// People who already liked the current user. Tapping opens their profile,
/// where a like-back creates the match.
class LikesScreen extends ConsumerWidget {
  const LikesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_likesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Likes')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_likesProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (likes) {
            if (likes.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.favorite_border, size: 56),
                SizedBox(height: 12),
                Center(child: Text('No likes yet.\nKeep swiping!', textAlign: TextAlign.center)),
              ]);
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72),
              itemCount: likes.length,
              itemBuilder: (_, i) => _LikeTile(card: likes[i]),
            );
          },
        ),
      ),
    );
  }
}

class _LikeTile extends StatelessWidget {
  final ProfileCard card;
  const _LikeTile({required this.card});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/profile/${card.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (card.primaryPhotoUrl != null)
              appNetworkImage(card.primaryPhotoUrl!, fit: BoxFit.cover)
            else
              const ColoredBox(color: Colors.black12, child: Icon(Icons.person, size: 64)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87]),
              ),
            ),
            Positioned(
              left: 10, bottom: 10, right: 10,
              child: Text('${card.displayName}, ${card.age}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
