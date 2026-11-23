import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/profile_card.dart';
import '../../shared/widgets/photo_pager.dart';
import '../matches/match_dialog.dart';
import 'discover_repository.dart';
import 'filters_sheet.dart';

final _discoverProvider =
    FutureProvider.autoDispose<List<ProfileCard>>((ref) => DiscoverRepository().feed());

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _repo = DiscoverRepository();
  List<ProfileCard> _deck = [];
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(_discoverProvider, (_, next) {
      next.whenData((cards) => setState(() {
            _deck = List.of(cards);
            _loaded = true;
          }));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () async {
              final changed = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const FiltersSheet(),
              );
              if (changed == true) ref.invalidate(_discoverProvider);
            },
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final async = ref.watch(_discoverProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Empty(
        icon: Icons.error_outline,
        text: 'Could not load profiles.\n$e',
        action: () => ref.invalidate(_discoverProvider),
      ),
      data: (_) {
        if (_loaded && _deck.isEmpty) {
          return _Empty(
            icon: Icons.search_off,
            text: 'No more people nearby.\nTry widening your filters.',
            action: () => ref.invalidate(_discoverProvider),
          );
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
    );
  }

  Widget _cardStack() {
    return Stack(
      children: [
        for (var i = _deck.length - 1; i >= 0 && i >= _deck.length - 3; i--)
          if (i == _deck.length - 1)
            _SwipeableCard(
              key: ValueKey(_deck[i].id),
              card: _deck[i],
              onSwiped: (action) => _handleSwipe(_deck[i], action),
              onTap: () => context.push('/profile/${_deck[i].id}'),
            )
          else
            Positioned.fill(child: _DiscoverCardView(card: _deck[i])),
      ].reversed.toList(),
    );
  }

  Widget _actionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleBtn(Icons.close, Colors.redAccent, () => _swipeTop('pass')),
        _circleBtn(Icons.star, Colors.blueAccent, () => _swipeTop('superlike'), size: 48),
        _circleBtn(Icons.favorite, Colors.green, () => _swipeTop('like')),
      ],
    );
  }

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap, {double size = 60}) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: size * 0.5),
      ),
    );
  }

  void _swipeTop(String action) {
    if (_deck.isEmpty) return;
    _handleSwipe(_deck.last, action);
  }

  Future<void> _handleSwipe(ProfileCard card, String action) async {
    setState(() => _deck.removeWhere((c) => c.id == card.id));
    try {
      final res = await _repo.swipe(card.id, action);
      if (res.matched && mounted) {
        await showMatchDialog(context, card, res.conversationId!);
      }
    } catch (_) {/* swallow; swipe is idempotent server-side */}
    if (_deck.length <= 2) ref.invalidate(_discoverProvider);
  }
}

/// A draggable top card.
class _SwipeableCard extends StatefulWidget {
  final ProfileCard card;
  final void Function(String action) onSwiped;
  final VoidCallback onTap;
  const _SwipeableCard({super.key, required this.card, required this.onSwiped, required this.onTap});
  @override
  State<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<_SwipeableCard> {
  Offset _drag = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final angle = _drag.dx / 1000;
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onTap,
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
            angle: angle,
            child: Stack(
              children: [
                _DiscoverCardView(card: widget.card),
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
                    color: like ? Colors.green : Colors.red,
                    fontSize: 28,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      );
}

/// The visual card: photo carousel + name/age/distance/bio overlay.
class _DiscoverCardView extends StatelessWidget {
  final ProfileCard card;
  const _DiscoverCardView({required this.card});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoPager(urls: card.photoUrls),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('${card.displayName}, ${card.age}',
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                    ),
                    if (card.isVerified)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.verified, color: Colors.lightBlueAccent, size: 22),
                      ),
                  ],
                ),
                if (card.distanceKm != null)
                  Text(card.distanceLabel, style: const TextStyle(color: Colors.white70)),
                if (card.bio != null && card.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(card.bio!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback action;
  const _Empty({required this.icon, required this.text, required this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: action, child: const Text('Refresh')),
          ],
        ),
      );
}
