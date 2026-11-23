import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../shared/models/message.dart';
import '../../shared/models/profile_card.dart';
import '../../shared/widgets/app_image.dart';
import 'chat_repository.dart';

/// 1:1 realtime chat room: live messages, presence (online/typing), read
/// receipts, text + image messages.
class ChatRoomScreen extends StatefulWidget {
  final String conversationId;
  final ProfileCard? other;
  const ChatRoomScreen({super.key, required this.conversationId, this.other});
  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _repo = ChatRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final RealtimeChannel _channel;
  Timer? _typingTimer;

  bool _otherOnline = false;
  bool _otherTyping = false;

  @override
  void initState() {
    super.initState();
    _repo.markRead(widget.conversationId);
    _setupPresence();
  }

  void _setupPresence() {
    _channel = _repo.presenceChannel(widget.conversationId);
    _channel
        .onPresenceSync((_) {
          final states = _channel.presenceState();
          final others = states
              .expand((s) => s.presences)
              .where((p) => (p.payload['uid'] as String?) != Db.uid);
          if (mounted) setState(() => _otherOnline = others.isNotEmpty);
        })
        .onBroadcast(
            event: 'typing',
            callback: (payload) {
              if (payload['uid'] == Db.uid) return;
              if (mounted) setState(() => _otherTyping = payload['typing'] == true);
            })
        .subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel.track({'uid': Db.uid});
      }
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    Db.client.removeChannel(_channel);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTyping(String _) {
    _channel.sendBroadcastMessage(event: 'typing', payload: {'uid': Db.uid, 'typing': true});
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _channel.sendBroadcastMessage(event: 'typing', payload: {'uid': Db.uid, 'typing': false});
    });
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _repo.sendText(widget.conversationId, text);
  }

  Future<void> _sendImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    await _repo.sendImage(widget.conversationId, File(picked.path), picked.name.split('.').last);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.other?.displayName ?? 'Chat';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: widget.other == null ? null : () => context.push('/profile/${widget.other!.id}'),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.other?.primaryPhotoUrl != null
                    ? appImageProvider(widget.other!.primaryPhotoUrl!)
                    : null,
                child: widget.other?.primaryPhotoUrl == null ? const Icon(Icons.person, size: 18) : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 16)),
                  Text(
                    _otherTyping ? 'typing…' : (_otherOnline ? 'online' : 'offline'),
                    style: TextStyle(
                        fontSize: 12,
                        color: _otherOnline ? Colors.green : Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _messageList()),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _messageList() {
    return StreamBuilder<List<Message>>(
      stream: _repo.messageStream(widget.conversationId),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final messages = snap.data!;
        // mark incoming as read whenever new ones arrive while the room is open
        if (messages.any((m) => m.senderId != Db.uid && m.readAt == null)) {
          _repo.markRead(widget.conversationId);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          }
        });
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(12),
          itemCount: messages.length,
          itemBuilder: (_, i) => _Bubble(message: messages[i]),
        );
      },
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.photo_outlined), onPressed: _sendImage),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onTyping,
                decoration: const InputDecoration(hintText: 'Message…', isDense: true),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(icon: const Icon(Icons.send), onPressed: _sendText),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.senderId == Db.uid;
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: mine ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.kind == 'image' && message.mediaPath != null)
              _MediaImage(path: message.mediaPath!)
            else
              Text(message.body ?? '',
                  style: TextStyle(color: mine ? Colors.white : cs.onSurface)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(DateFormat.Hm().format(message.createdAt.toLocal()),
                    style: TextStyle(
                        fontSize: 10,
                        color: (mine ? Colors.white : cs.onSurface).withValues(alpha: 0.7))),
                if (mine) ...[
                  const SizedBox(width: 3),
                  Icon(message.readAt != null ? Icons.done_all : Icons.done,
                      size: 14,
                      color: message.readAt != null ? Colors.lightBlueAccent : Colors.white70),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaImage extends StatelessWidget {
  final String path;
  const _MediaImage({required this.path});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Db.chatMediaUrl(path),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 180, width: 180, child: Center(child: CircularProgressIndicator()));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: appNetworkImage(snap.data!, width: 200, fit: BoxFit.cover),
        );
      },
    );
  }
}
