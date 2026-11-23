import 'profile_card.dart';

/// A row in the Chats list, from the get_conversations() RPC.
class ConversationSummary {
  final String conversationId;
  final String matchId;
  final ProfileCard other;
  final String? lastBody;
  final String? lastKind;
  final String? lastSenderId;
  final DateTime? lastMessageAt;
  final int unreadCount;

  ConversationSummary({
    required this.conversationId,
    required this.matchId,
    required this.other,
    required this.lastBody,
    required this.lastKind,
    required this.lastSenderId,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> j) {
    final last = j['last_message'] as Map<String, dynamic>?;
    return ConversationSummary(
      conversationId: j['conversation_id'] as String,
      matchId: j['match_id'] as String,
      other: ProfileCard.fromJson(j['other'] as Map<String, dynamic>),
      lastBody: last?['body'] as String?,
      lastKind: last?['kind'] as String?,
      lastSenderId: last?['sender_id'] as String?,
      lastMessageAt: j['last_message_at'] == null
          ? null
          : DateTime.parse(j['last_message_at'] as String),
      unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  String get preview {
    if (lastBody == null && lastKind == null) return 'Say hi 👋';
    if (lastKind == 'image') return '📷 Photo';
    return lastBody ?? '';
  }
}
