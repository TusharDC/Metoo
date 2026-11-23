import '../../core/config.dart';
import '../../core/demo/demo_store.dart';
import '../../core/supabase.dart';
import '../../shared/models/ai_character.dart';
import '../../shared/models/ai_match.dart';
import '../../shared/models/ai_message.dart';

class AiReply {
  final String text;
  final String? voicePath;
  AiReply(this.text, this.voicePath);
}

class AiRepository {
  DemoStore get _demo => DemoStore.instance;

  Future<List<AiCharacter>> characters() async {
    final rows = AppConfig.demo
        ? _demo.characters()
        : await Db.client.rpc('get_characters');
    return (rows as List).map((e) => AiCharacter.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// The swipe deck of AI girls the user hasn't swiped yet.
  Future<List<AiCharacter>> discoverFeed({int limit = 20}) async {
    final rows = AppConfig.demo
        ? _demo.discoverFeed(limit: limit)
        : await Db.client.rpc('get_ai_discover_feed', params: {'p_limit': limit});
    return (rows as List).map((e) => AiCharacter.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Record a swipe. like/superlike silently queues a match that reveals later
  /// in the Matches tab (3-5 min, superlike faster). No instant popup.
  Future<void> swipe(int characterId, String action) async {
    if (AppConfig.demo) return _demo.swipe(characterId, action);
    await Db.client.rpc('ai_swipe', params: {'p_character_id': characterId, 'p_action': action});
  }

  Future<void> resetSwipes() async {
    if (AppConfig.demo) return _demo.resetSwipes();
    await Db.client.rpc('reset_ai_swipes');
  }

  /// Revealed matches for the Matches tab.
  Future<List<AiMatch>> matches() async {
    final rows = AppConfig.demo ? _demo.matches() : await Db.client.rpc('get_ai_matches');
    return (rows as List).map((e) => AiMatch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> startConversation(int characterId, {String? mood}) async {
    if (AppConfig.demo) return _demo.startConversation(characterId, mood: mood);
    final id = await Db.client.rpc('start_ai_conversation',
        params: {'p_character_id': characterId, 'p_mood': mood});
    return id as String;
  }

  Future<void> setMood(String conversationId, String mood) async {
    if (AppConfig.demo) return _demo.setMood(conversationId, mood);
    await Db.client.rpc('set_ai_mood', params: {'p_conversation': conversationId, 'p_mood': mood});
  }

  Future<List<AiMessage>> history(String conversationId) async {
    final rows = AppConfig.demo
        ? _demo.history(conversationId)
        : await Db.client.rpc('get_ai_history', params: {'p_conversation': conversationId});
    return (rows as List).map((e) => AiMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Sends a message to the character and returns its reply (ai-chat function).
  Future<AiReply> send(String conversationId, String message, {bool wantVoice = false}) async {
    if (AppConfig.demo) {
      final d = await _demo.send(conversationId, message);
      return AiReply(d['text'] as String, null);
    }
    final res = await Db.client.functions.invoke('ai-chat', body: {
      'conversation_id': conversationId,
      'message': message,
      'want_voice': wantVoice,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return AiReply(data['text'] as String? ?? '…', data['voice_path'] as String?);
  }

  /// Requests an AI photo (Imagen). Returns the stored media path.
  Future<String> selfie(String conversationId, {String? scene}) async {
    if (AppConfig.demo) throw Exception('Photos need a live backend (demo build)');
    final res = await Db.client.functions.invoke('ai-selfie', body: {
      'conversation_id': conversationId,
      'scene': scene,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['image_path'] == null) throw Exception(data['error'] ?? 'failed');
    return data['image_path'] as String;
  }

  /// Requests an AI video clip (Veo). Resolves when done, retrying while the
  /// long-running job is still pending.
  Future<String> video(String conversationId, {String? scene}) async {
    if (AppConfig.demo) throw Exception('Videos need a live backend (demo build)');
    String? operation;
    for (var attempt = 0; attempt < 6; attempt++) {
      final res = await Db.client.functions.invoke('ai-video', body: {
        'conversation_id': conversationId,
        'scene': scene,
        'operation': operation,
      });
      final data = res.data as Map<String, dynamic>;
      if (data['status'] == 'done') return data['video_path'] as String;
      if (data['status'] == 'pending') {
        operation = data['operation'] as String?;
        continue;
      }
      throw Exception(data['error'] ?? 'video failed');
    }
    throw Exception('Video is taking too long. Try again shortly.');
  }
}
