import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/ai_match.dart';
import '../../shared/widgets/app_image.dart';
import 'ai_repository.dart';

final _matchesProvider =
    FutureProvider.autoDispose<List<AiMatch>>((ref) => AiRepository().matches());

/// Matches tab — girls who liked you back (revealed after the delay).
class AiMatchesScreen extends ConsumerStatefulWidget {
  const AiMatchesScreen({super.key});
  @override
  ConsumerState<AiMatchesScreen> createState() => _AiMatchesScreenState();
}

class _AiMatchesScreenState extends ConsumerState<AiMatchesScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Matches reveal over 3-5 min — poll so new ones appear without manual refresh.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => ref.invalidate(_matchesProvider));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_matchesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_matchesProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (matches) {
            if (matches.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 140),
                Icon(Icons.favorite_border, size: 56),
                SizedBox(height: 12),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text('No matches yet.\nSwipe right on Discover — they reply in a few minutes 😉',
                        textAlign: TextAlign.center),
                  ),
                ),
              ]);
            }
            final fresh = matches.where((m) => m.isNew).toList();
            return ListView(
              children: [
                if (fresh.isNotEmpty) _newMatchesRow(context, fresh),
                ...matches.map((m) => _MatchTile(
                      match: m,
                      onReturn: () => ref.invalidate(_matchesProvider),
                    )),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _newMatchesRow(BuildContext context, List<AiMatch> fresh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Matches',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4)),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: fresh.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final m = fresh[i];
                final url = m.character.avatarUrl;
                return GestureDetector(
                  onTap: () async {
                    await context.push('/ai-chat/${m.conversationId}', extra: m.character);
                    ref.invalidate(_matchesProvider);
                  },
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundImage: url != null ? appImageProvider(url) : null,
                        child: url == null ? Text(m.character.name[0]) : null,
                      ),
                      const SizedBox(height: 4),
                      Text(m.character.name, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 24),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Messages', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  final AiMatch match;
  final VoidCallback onReturn;
  const _MatchTile({required this.match, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final url = match.character.avatarUrl;
    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundImage: url != null ? appImageProvider(url) : null,
        child: url == null ? const Icon(Icons.person) : null,
      ),
      title: Text(match.character.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(match.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: match.isNew
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10)),
              child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 10)),
            )
          : null,
      onTap: () async {
        await context.push('/ai-chat/${match.conversationId}', extra: match.character);
        onReturn();
      },
    );
  }
}
