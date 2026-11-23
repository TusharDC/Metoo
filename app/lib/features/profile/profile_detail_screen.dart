import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/profile_card.dart';
import '../../shared/widgets/photo_pager.dart';
import '../discover/discover_repository.dart';
import '../matches/match_dialog.dart';
import 'moderation_repository.dart';
import 'profile_repository.dart';

final _detailProvider = FutureProvider.autoDispose.family<ProfileCard, String>(
  (ref, id) async => ProfileCard.fromJson(await ProfileRepository().card(id)),
);

/// Read-only view of another user, with Like / Block / Report actions.
class ProfileDetailScreen extends ConsumerWidget {
  final String profileId;
  const ProfileDetailScreen({super.key, required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_detailProvider(profileId));
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Unavailable.\n$e', textAlign: TextAlign.center)),
        data: (card) => _content(context, card),
      ),
      floatingActionButton: async.maybeWhen(
        data: (card) => FloatingActionButton.extended(
          icon: const Icon(Icons.favorite),
          label: const Text('Like'),
          onPressed: () async {
            final res = await DiscoverRepository().swipe(card.id, 'like');
            if (res.matched && context.mounted) {
              await showMatchDialog(context, card, res.conversationId!);
            } else if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Liked!')));
            }
          },
        ),
        orElse: () => null,
      ),
    );
  }

  Widget _content(BuildContext context, ProfileCard card) => ListView(
        children: [
          AspectRatio(aspectRatio: 0.85, child: PhotoPager(urls: card.photoUrls)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('${card.displayName}, ${card.age}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  if (card.isVerified)
                    const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, color: Colors.blue)),
                ]),
                if (card.distanceKm != null) Text(card.distanceLabel),
                if (card.bio != null && card.bio!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(card.bio!),
                ],
                if (card.interests.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: card.interests.map((i) => Chip(label: Text(i))).toList()),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      );

  Future<void> _onMenu(BuildContext context, String action) async {
    final repo = ModerationRepository();
    if (action == 'block') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Block user?'),
          content: const Text('They won\'t be able to see you or message you, and any match is removed.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Block')),
          ],
        ),
      );
      if (ok == true) {
        await repo.block(profileId);
        if (context.mounted) context.pop();
      }
    } else if (action == 'report') {
      final reason = await showModalBottomSheet<String>(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ModerationRepository.reasons
                .map((r) => ListTile(title: Text(r), onTap: () => Navigator.pop(context, r)))
                .toList(),
          ),
        ),
      );
      if (reason != null) {
        await repo.report(profileId, reason);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Report submitted. Thank you.')));
        }
      }
    }
  }
}
