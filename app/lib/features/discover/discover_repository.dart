import '../../core/supabase.dart';
import '../../shared/models/profile_card.dart';

class SwipeResult {
  final bool matched;
  final String? conversationId;
  SwipeResult(this.matched, this.conversationId);
}

class DiscoverRepository {
  Future<List<ProfileCard>> feed({int limit = 20}) async {
    final rows = await Db.client.rpc('get_discover_feed', params: {'p_limit': limit});
    return (rows as List)
        .map((e) => ProfileCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SwipeResult> swipe(String targetId, String action) async {
    final res = await Db.client
        .rpc('swipe', params: {'target': targetId, 'p_action': action}) as Map<String, dynamic>;
    return SwipeResult(res['matched'] as bool? ?? false, res['conversation_id'] as String?);
  }

  Future<List<ProfileCard>> incomingLikes() async {
    final rows = await Db.client.rpc('get_incoming_likes');
    return (rows as List)
        .map((e) => ProfileCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
