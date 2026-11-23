import '../../core/supabase.dart';

class AiCharacter {
  final int id;
  final String slug;
  final String name;
  final String? tagline;
  final String? bio;
  final String personality;
  final String? avatarPath;
  final String accentColor;
  final String defaultMood;
  final List<String> traits;

  AiCharacter({
    required this.id,
    required this.slug,
    required this.name,
    required this.tagline,
    required this.bio,
    required this.personality,
    required this.avatarPath,
    required this.accentColor,
    required this.defaultMood,
    required this.traits,
  });

  factory AiCharacter.fromJson(Map<String, dynamic> j) => AiCharacter(
        id: (j['id'] as num).toInt(),
        slug: j['slug'] as String,
        name: j['name'] as String,
        tagline: j['tagline'] as String?,
        bio: j['bio'] as String?,
        personality: j['personality'] as String,
        avatarPath: j['avatar_path'] as String?,
        accentColor: (j['accent_color'] as String?) ?? '#E91E63',
        defaultMood: (j['default_mood'] as String?) ?? 'playful',
        traits: (j['traits'] as List? ?? []).map((e) => e.toString()).toList(),
      );

  String? get avatarUrl =>
      avatarPath == null ? null : Db.client.storage.from('characters').getPublicUrl(avatarPath!);
}
