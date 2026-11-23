import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/ai_character.dart';
import '../../shared/widgets/app_image.dart';
import 'ai_repository.dart';

final _charactersProvider =
    FutureProvider.autoDispose<List<AiCharacter>>((ref) => AiRepository().characters());

/// Character picker for the AI-companion experience.
class CompanionsScreen extends ConsumerWidget {
  const CompanionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_charactersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Companions'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('A little flirting. A lot of Shararat.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load companions.\n$e', textAlign: TextAlign.center)),
        data: (chars) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 0.74),
          itemCount: chars.length,
          itemBuilder: (_, i) => _CharacterCard(character: chars[i]),
        ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  final AiCharacter character;
  const _CharacterCard({required this.character});

  Color get _accent {
    final hex = character.accentColor.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final id = await AiRepository()
            .startConversation(character.id, mood: character.defaultMood);
        if (context.mounted) context.push('/ai-chat/$id', extra: character);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (character.avatarUrl != null)
              appNetworkImage(character.avatarUrl!, fit: BoxFit.cover)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [_accent.withValues(alpha: 0.85), _accent.withValues(alpha: 0.45)]),
                ),
                child: Center(
                  child: Text(character.name[0],
                      style: const TextStyle(fontSize: 56, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87]),
              ),
            ),
            Positioned(
              left: 12, right: 12, bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(character.name,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(character.personality,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
