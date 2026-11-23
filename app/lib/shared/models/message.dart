class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String kind; // text | image | system
  final String? body;
  final String? mediaPath;
  final DateTime? readAt;
  final DateTime createdAt;

  /// Client-side only: optimistic send state before the server ack.
  final bool pending;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.kind,
    required this.body,
    required this.mediaPath,
    required this.readAt,
    required this.createdAt,
    this.pending = false,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        senderId: j['sender_id'] as String,
        kind: j['kind'] as String,
        body: j['body'] as String?,
        mediaPath: j['media_path'] as String?,
        readAt: j['read_at'] == null ? null : DateTime.parse(j['read_at'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
