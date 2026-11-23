import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/supabase.dart';
import '../../shared/models/conversation_summary.dart';
import '../../shared/models/message.dart';

class ChatRepository {
  Future<List<ConversationSummary>> conversations() async {
    // Human-to-human chat has no demo fixtures — the tab shows its empty state.
    if (AppConfig.demo) return const [];
    final rows = await Db.client.rpc('get_conversations');
    return (rows as List)
        .map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Live-ordered message stream for a conversation (Supabase Realtime).
  Stream<List<Message>> messageStream(String conversationId) {
    return Db.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows.map(Message.fromJson).toList());
  }

  Future<void> sendText(String conversationId, String body) async {
    await Db.client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': Db.uid,
      'kind': 'text',
      'body': body,
    });
  }

  Future<void> sendImage(String conversationId, File file, String ext) async {
    final path = '$conversationId/${Db.uid}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await Db.client.storage.from('chat-media').upload(path, file);
    await Db.client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': Db.uid,
      'kind': 'image',
      'media_path': path,
    });
  }

  Future<void> markRead(String conversationId) =>
      Db.client.rpc('mark_read', params: {'p_conversation': conversationId});

  /// Presence + typing channel for a conversation. Caller subscribes.
  RealtimeChannel presenceChannel(String conversationId) =>
      Db.client.channel('room:$conversationId',
          opts: const RealtimeChannelConfig(self: false));
}
