import 'demo_data.dart';

/// In-memory stand-in for the whole Supabase backend, used when
/// [AppConfig.demo] is on. State lives for the life of the process only —
/// killing the app resets everything.
///
/// Behaviour mirrors the real RPCs (`0008_ai_tinder.sql`, `0009_delayed_match.sql`)
/// with one deliberate difference: match reveal delays are compressed from
/// 3-5 min / 30-60 s down to seconds, so the delayed-match flow is actually
/// observable in a sitting. See [_revealDelay].
class DemoStore {
  DemoStore._() {
    _seed();
  }
  static final DemoStore instance = DemoStore._();

  final List<Map<String, dynamic>> _characters = demoCharacters();

  /// character_id -> 'like' | 'pass' | 'superlike'
  final Map<int, String> _swipes = {};

  /// conversation_id -> conversation
  final Map<String, _Conv> _convs = {};

  Map<String, dynamic> _settings = demoSettings();
  Map<String, dynamic> _profile = demoMyProfile();

  int _replyCursor = 0;

  /// Three pre-matched girls with history, so the Matches tab and chat screens
  /// aren't empty on first launch. The rest behave exactly like production.
  void _seed() {
    for (final slug in ['aanya', 'riya', 'meera']) {
      final c = _characters.firstWhere((x) => x['slug'] == slug);
      final id = c['id'] as int;
      _swipes[id] = 'like';
      final conv = _Conv(
        id: 'demo-conv-$slug',
        characterId: id,
        mood: c['default_mood'] as String,
        revealedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      conv.messages.add(_Msg('assistant', 'text', demoOpener(slug), null,
          DateTime.now().subtract(const Duration(minutes: 4))));
      if (slug == 'aanya') {
        conv.messages
          ..add(_Msg('user', 'text', 'ouch 😄 i was being fashionably late',
              null, DateTime.now().subtract(const Duration(minutes: 3))))
          ..add(_Msg('assistant', 'text', 'sure sure. what\'s your excuse gonna be tomorrow',
              null, DateTime.now().subtract(const Duration(minutes: 2))));
      }
      _convs[conv.id] = conv;
    }
  }

  // ---------------------------------------------------------------- characters

  List<Map<String, dynamic>> characters() => List.of(_characters);

  /// Deck of girls not yet swiped — mirrors `get_ai_discover_feed`.
  List<Map<String, dynamic>> discoverFeed({int limit = 20}) => _characters
      .where((c) => !_swipes.containsKey(c['id'] as int))
      .take(limit)
      .map((c) => Map<String, dynamic>.of(c))
      .toList();

  void resetSwipes() {
    _swipes.clear();
    _convs.clear();
    _seed();
  }

  // -------------------------------------------------------------------- swipes

  Duration _revealDelay(String action) =>
      action == 'superlike' ? const Duration(seconds: 8) : const Duration(seconds: 25);

  /// Mirrors `ai_swipe`: pass is recorded, like/superlike queues a conversation
  /// that reveals in the Matches tab after a delay.
  void swipe(int characterId, String action) {
    _swipes[characterId] = action;
    if (action == 'pass') return;
    final existing = _convs.values.where((c) => c.characterId == characterId);
    if (existing.isNotEmpty) return;
    final c = _characters.firstWhere((x) => x['id'] == characterId);
    final conv = _Conv(
      id: 'demo-conv-${c['slug']}',
      characterId: characterId,
      mood: c['default_mood'] as String,
      revealedAt: DateTime.now().add(_revealDelay(action)),
    );
    _convs[conv.id] = conv;
  }

  // ------------------------------------------------------------------- matches

  /// Mirrors `get_ai_matches`: only conversations whose reveal time has passed.
  List<Map<String, dynamic>> matches() {
    final now = DateTime.now();
    final revealed = _convs.values.where((c) => !c.revealedAt.isAfter(now)).toList()
      ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return revealed.map((c) {
      final ch = _characters.firstWhere((x) => x['id'] == c.characterId);
      final last = c.messages.isEmpty ? null : c.messages.last;
      return <String, dynamic>{
        'conversation_id': c.id,
        'revealed_at': c.revealedAt.toIso8601String(),
        'character': Map<String, dynamic>.of(ch),
        'last_message': last == null
            ? null
            : {
                'role': last.role,
                'kind': last.kind,
                'content': last.content,
                'created_at': last.createdAt.toIso8601String(),
              },
        'is_new': c.messages.isEmpty,
      };
    }).toList();
  }

  String startConversation(int characterId, {String? mood}) {
    final existing = _convs.values.where((c) => c.characterId == characterId);
    if (existing.isNotEmpty) {
      final c = existing.first;
      // Companions-grid opens are visible immediately, as in 0009.
      if (c.revealedAt.isAfter(DateTime.now())) c.revealedAt = DateTime.now();
      if (mood != null) c.mood = mood;
      return c.id;
    }
    final ch = _characters.firstWhere((x) => x['id'] == characterId);
    final conv = _Conv(
      id: 'demo-conv-${ch['slug']}',
      characterId: characterId,
      mood: mood ?? ch['default_mood'] as String,
      revealedAt: DateTime.now(),
    );
    _swipes[characterId] = 'like';
    _convs[conv.id] = conv;
    return conv.id;
  }

  void setMood(String conversationId, String mood) {
    _convs[conversationId]?.mood = mood;
  }

  // -------------------------------------------------------------------- chat

  List<Map<String, dynamic>> history(String conversationId) =>
      (_convs[conversationId]?.messages ?? const <_Msg>[])
          .map((m) => m.toJson())
          .toList();

  /// Stands in for the `ai-chat` Edge Function. No LLM, no network — a rotating
  /// canned reply after a short delay so the typing bubble is visible.
  Future<Map<String, dynamic>> send(String conversationId, String message) async {
    final conv = _convs[conversationId];
    if (conv == null) return {'text': '…'};
    conv.messages.add(_Msg('user', 'text', message, null, DateTime.now()));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final text = demoReplies[_replyCursor++ % demoReplies.length];
    conv.messages.add(_Msg('assistant', 'text', text, null, DateTime.now()));
    conv.lastMessageAt = DateTime.now();
    return {'text': text, 'voice_path': null};
  }

  // ---------------------------------------------------------------- profile

  Map<String, dynamic> myProfile() => Map<String, dynamic>.of(_profile);

  void saveProfile({String? displayName, String? bio}) {
    _profile = {
      ..._profile,
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
    };
  }

  void setInterests(List<String> slugs) {
    final all = demoInterests();
    _profile = {
      ..._profile,
      'interests': slugs,
      'interest_labels': all
          .where((i) => slugs.contains(i['slug']))
          .map((i) => i['label'] as String)
          .toList(),
    };
  }

  // --------------------------------------------------------------- settings

  Map<String, dynamic> settings() =>
      {..._settings, 'is_discoverable': _profile['is_discoverable']};

  void setSetting(String key, bool value) {
    if (key == 'is_discoverable') {
      _profile = {..._profile, 'is_discoverable': value};
    } else {
      _settings = {..._settings, key: value};
    }
  }
}

class _Conv {
  _Conv({
    required this.id,
    required this.characterId,
    required this.mood,
    required this.revealedAt,
  });

  final String id;
  final int characterId;
  String mood;
  DateTime revealedAt;
  DateTime? lastMessageAt;
  final List<_Msg> messages = [];

  DateTime get sortKey => lastMessageAt ?? revealedAt;
}

class _Msg {
  _Msg(this.role, this.kind, this.content, this.mediaPath, this.createdAt);

  final String role;
  final String kind;
  final String? content;
  final String? mediaPath;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': 'demo-${createdAt.microsecondsSinceEpoch}-$role',
        'role': role,
        'kind': kind,
        'content': content,
        'media_path': mediaPath,
        'created_at': createdAt.toIso8601String(),
      };
}
