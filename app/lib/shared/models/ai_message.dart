class AiMessage {
  final String id;
  final String role; // user | assistant
  final String kind; // text | voice | image (image also used for video clips)
  final String? content;
  final String? mediaPath;
  final DateTime createdAt;
  final bool pending;

  AiMessage({
    required this.id,
    required this.role,
    required this.kind,
    required this.content,
    required this.mediaPath,
    required this.createdAt,
    this.pending = false,
  });

  bool get isUser => role == 'user';
  bool get isVideo => mediaPath != null && mediaPath!.endsWith('.mp4');

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        id: j['id'] as String,
        role: j['role'] as String,
        kind: j['kind'] as String,
        content: j['content'] as String?,
        mediaPath: j['media_path'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
