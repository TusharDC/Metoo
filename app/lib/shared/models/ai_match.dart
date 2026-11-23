import 'ai_character.dart';

/// A revealed AI match shown in the Matches tab.
class AiMatch {
  final String conversationId;
  final AiCharacter character;
  final String? lastRole; // 'user' | 'assistant'
  final String? lastKind;
  final String? lastContent;
  final bool isNew;

  AiMatch({
    required this.conversationId,
    required this.character,
    required this.lastRole,
    required this.lastKind,
    required this.lastContent,
    required this.isNew,
  });

  factory AiMatch.fromJson(Map<String, dynamic> j) {
    final last = j['last_message'] as Map<String, dynamic>?;
    return AiMatch(
      conversationId: j['conversation_id'] as String,
      character: AiCharacter.fromJson(j['character'] as Map<String, dynamic>),
      lastRole: last?['role'] as String?,
      lastKind: last?['kind'] as String?,
      lastContent: last?['content'] as String?,
      isNew: j['is_new'] as bool? ?? false,
    );
  }

  String get preview {
    if (lastContent == null && lastKind == null) return 'New match — say hi 💕';
    if (lastKind == 'image') return '📷 Photo';
    if (lastKind == 'voice') return '🎙️ Voice note';
    final who = lastRole == 'user' ? 'You: ' : '';
    return '$who${lastContent ?? ''}';
  }
}
