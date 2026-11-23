import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../shared/models/ai_character.dart';
import '../../shared/widgets/app_image.dart';
import 'ai_repository.dart';

final _aiFeedProvider =
    FutureProvider.autoDispose<List<AiCharacter>>((ref) => AiRepository().discoverFeed());

/// The "AI Tinder" deck: swipe through AI girls. Right-swipe = instant match.
class AiDiscoverScreen extends ConsumerStatefulWidget {
  const AiDiscoverScreen({super.key});
  @override
  ConsumerState<AiDiscoverScreen> createState() => _AiDiscoverScreenState();
}

class _AiDiscoverScreenState extends ConsumerState<AiDiscoverScreen> {
  final _repo = AiRepository();
  List<AiCharacter> _deck = [];
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(_aiFeedProvider, (_, next) {
      next.whenData((cards) => setState(() {
            _deck = List.of(cards);
            _loaded = true;
          }));
    });
    final async = ref.watch(_aiFeedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppConfig.demo ? 'Discover · DEMO' : 'Discover'),
        actions: [
          IconButton(
            tooltip: 'Reset deck',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _repo.resetSwipes();
              ref.invalidate(_aiFeedProvider);
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load.\n$e', textAlign: TextAlign.center)),
        data: (_) {
          if (_loaded && _deck.isEmpty) {
            return _empty();
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                Expanded(child: _cardStack()),
                const SizedBox(height: 12),
                _actionBar(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border, size: 56),
            const SizedBox(height: 12),
            const Text("That's everyone for now 💕", textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await _repo.resetSwipes();
                ref.invalidate(_aiFeedProvider);
              },
              child: const Text('Start over'),
            ),
          ],
        ),
      );

  Widget _cardStack() {
    return Stack(
      children: [
        for (var i = _deck.length - 1; i >= 0 && i >= _deck.length - 3; i--)
          if (i == _deck.length - 1)
            _SwipeableCard(
              key: ValueKey(_deck[i].id),
              character: _deck[i],
              onSwiped: (action) => _handle(_deck[i], action),
            )
          else
            Positioned.fill(child: _CardView(character: _deck[i])),
      ].reversed.toList(),
    );
  }

  Widget _actionBar() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _btn(Icons.close, Colors.redAccent, () => _top('pass')),
          _btn(Icons.star, Colors.blueAccent, () => _top('superlike'), size: 48),
          _btn(Icons.favorite, Colors.green, () => _top('like')),
        ],
      );

  Widget _btn(IconData icon, Color color, VoidCallback onTap, {double size = 60}) => GestureDetector(
        onTap: onTap,
        child: CircleAvatar(
          radius: size / 2,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: size * 0.5),
        ),
      );

  void _top(String action) {
    if (_deck.isNotEmpty) _handle(_deck.last, action);
  }

  Future<void> _handle(AiCharacter c, String action) async {
    setState(() => _deck.removeWhere((x) => x.id == c.id));
    if (action != 'pass' && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text(action == 'superlike'
              ? 'Superliked ${c.name} ⭐ — she might reply soon'
              : 'Liked ${c.name} 💕'),
        ));
    }
    try {
      await _repo.swipe(c.id, action); // match reveals later in Matches tab
    } catch (_) {/* idempotent server-side */}
    if (_deck.length <= 2) ref.invalidate(_aiFeedProvider);
  }
}

/// Draggable top card.
class _SwipeableCard extends StatefulWidget {
  final AiCharacter character;
  final void Function(String action) onSwiped;
  const _SwipeableCard({super.key, required this.character, required this.onSwiped});
  @override
  State<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<_SwipeableCard> {
  Offset _drag = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _drag += d.delta),
        onPanEnd: (_) {
          if (_drag.dx > 120) {
            widget.onSwiped('like');
          } else if (_drag.dx < -120) {
            widget.onSwiped('pass');
          } else {
            setState(() => _drag = Offset.zero);
          }
        },
        child: Transform.translate(
          offset: _drag,
          child: Transform.rotate(
            angle: _drag.dx / 1000,
            child: Stack(
              children: [
                _CardView(character: widget.character),
                if (_drag.dx.abs() > 30) _stamp(_drag.dx > 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stamp(bool like) => Positioned(
        top: 32,
        left: like ? 24 : null,
        right: like ? null : 24,
        child: Transform.rotate(
          angle: like ? -0.3 : 0.3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: like ? Colors.green : Colors.red, width: 3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(like ? 'LIKE' : 'NOPE',
                style: TextStyle(
                    color: like ? Colors.green : Colors.red, fontSize: 28, fontWeight: FontWeight.bold)),
          ),
        ),
      );
}

/// The visual card: photo + name/personality/bio overlay.
class _CardView extends StatelessWidget {
  final AiCharacter character;
  const _CardView({required this.character});

  /// Her accent colour, used for the no-photo fallback so a deck without
  /// uploaded avatars still reads as designed rather than broken.
  Color get _accent {
    final hex = character.accentColor.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (character.avatarUrl != null)
            appNetworkImage(character.avatarUrl!, fit: BoxFit.cover)
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_accent.withValues(alpha: 0.9), _accent.withValues(alpha: 0.4)],
                ),
              ),
              child: Center(
                child: Text(
                  character.name[0],
                  style: const TextStyle(
                      fontSize: 120, color: Colors.white54, fontWeight: FontWeight.bold),
                ),
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
            left: 20, right: 20, bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(character.name,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                Text(character.personality, style: const TextStyle(color: Colors.white70)),
                if (character.bio != null && character.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(character.bio!,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
