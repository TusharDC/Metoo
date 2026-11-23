import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/supabase.dart';
import '../../shared/models/ai_character.dart';
import '../../shared/models/ai_message.dart';
import '../../shared/widgets/app_image.dart';
import 'ai_repository.dart';

/// Chat with an AI character: text, voice-note replies, on-demand photos/videos,
/// and an adjustable mood.
class AiChatScreen extends StatefulWidget {
  final String conversationId;
  final AiCharacter? character;
  const AiChatScreen({super.key, required this.conversationId, this.character});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _repo = AiRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _voiceMode = false;
  String _mood = 'playful';

  static const _moods = ['playful', 'mischievous', 'slow burn', 'flirty', 'chill'];

  @override
  void initState() {
    super.initState();
    _mood = widget.character?.defaultMood ?? 'playful';
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final msgs = await _repo.history(widget.conversationId);
    setState(() {
      _messages
        ..clear()
        ..addAll(msgs);
      _loading = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _add(AiMessage m) {
    setState(() => _messages.add(m));
    _scrollToEnd();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    _add(AiMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user', kind: 'text', content: text, mediaPath: null,
      createdAt: DateTime.now(),
    ));
    setState(() => _sending = true);
    try {
      final reply = await _repo.send(widget.conversationId, text, wantVoice: _voiceMode);
      _add(AiMessage(
        id: 'r-${DateTime.now().microsecondsSinceEpoch}',
        role: 'assistant',
        kind: reply.voicePath != null ? 'voice' : 'text',
        content: reply.text, mediaPath: reply.voicePath,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      _snack('Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _requestMedia({required bool video}) async {
    setState(() => _sending = true);
    _snack(video ? 'Making a video… this can take a minute' : 'Taking a selfie…');
    try {
      final path = video
          ? await _repo.video(widget.conversationId)
          : await _repo.selfie(widget.conversationId);
      _add(AiMessage(
        id: 'm-${DateTime.now().microsecondsSinceEpoch}',
        role: 'assistant', kind: 'image',
        content: null, mediaPath: path, createdAt: DateTime.now(),
      ));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _changeMood(String mood) async {
    setState(() => _mood = mood);
    await _repo.setMood(widget.conversationId, mood);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final name = widget.character?.name ?? 'Companion';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.character?.avatarUrl != null
                  ? appImageProvider(widget.character!.avatarUrl!)
                  : null,
              child: widget.character?.avatarUrl == null
                  ? Text(name[0]) : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16)),
                Text('mood: $_mood', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.mood),
            onSelected: _changeMood,
            itemBuilder: (_) =>
                _moods.map((m) => PopupMenuItem(value: m, child: Text(m))).toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _messages.length) return const _TypingBubble();
                      return _AiBubble(message: _messages[i]);
                    },
                  ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Ask for a photo',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: _sending ? null : () => _requestMedia(video: false),
            ),
            IconButton(
              tooltip: 'Ask for a video',
              icon: const Icon(Icons.movie_creation_outlined),
              onPressed: _sending ? null : () => _requestMedia(video: true),
            ),
            IconButton(
              tooltip: 'Voice replies',
              icon: Icon(_voiceMode ? Icons.graphic_eq : Icons.keyboard_voice_outlined,
                  color: _voiceMode ? Theme.of(context).colorScheme.primary : null),
              onPressed: () => setState(() => _voiceMode = !_voiceMode),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Message…', isDense: true),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(icon: const Icon(Icons.send), onPressed: _sending ? null : _send),
          ],
        ),
      ),
    );
  }
}

class _AiBubble extends StatelessWidget {
  final AiMessage message;
  const _AiBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.isUser;
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: message.kind == 'image'
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: mine ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: _content(context, mine, cs),
      ),
    );
  }

  Widget _content(BuildContext context, bool mine, ColorScheme cs) {
    if (message.kind == 'voice' && message.mediaPath != null) {
      return _VoiceNote(path: message.mediaPath!, caption: message.content, mine: mine);
    }
    if (message.kind == 'image' && message.mediaPath != null) {
      return message.isVideo
          ? _VideoNote(path: message.mediaPath!)
          : _ImageNote(path: message.mediaPath!, caption: message.content);
    }
    return Text(message.content ?? '',
        style: TextStyle(color: mine ? Colors.white : cs.onSurface));
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const SizedBox(
            height: 14, width: 32,
            child: Center(child: Text('…', style: TextStyle(fontSize: 20))),
          ),
        ),
      );
}

class _ImageNote extends StatelessWidget {
  final String path;
  final String? caption;
  const _ImageNote({required this.path, this.caption});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Db.aiMediaUrl(path),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 220, width: 180, child: Center(child: CircularProgressIndicator()));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: appNetworkImage(snap.data!, width: 220, fit: BoxFit.cover),
            ),
            if (caption != null && caption!.isNotEmpty)
              Padding(padding: const EdgeInsets.all(6), child: Text(caption!)),
          ],
        );
      },
    );
  }
}

class _VoiceNote extends StatefulWidget {
  final String path;
  final String? caption;
  final bool mine;
  const _VoiceNote({required this.path, this.caption, required this.mine});
  @override
  State<_VoiceNote> createState() => _VoiceNoteState();
}

class _VoiceNoteState extends State<_VoiceNote> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    final url = await Db.aiMediaUrl(widget.path);
    await _player.play(UrlSource(url));
    setState(() => _playing = true);
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.mine ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle, color: color),
          onPressed: _toggle,
        ),
        Icon(Icons.graphic_eq, color: color),
        if (widget.caption != null && widget.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(widget.caption!, style: TextStyle(color: color, fontSize: 12)),
            ),
          ),
      ],
    );
  }
}

class _VideoNote extends StatefulWidget {
  final String path;
  const _VideoNote({required this.path});
  @override
  State<_VideoNote> createState() => _VideoNoteState();
}

class _VideoNoteState extends State<_VideoNote> {
  VideoPlayerController? _controller;

  Future<void> _init() async {
    final url = await Db.aiMediaUrl(widget.path);
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    await c.initialize();
    await c.setLooping(true);
    await c.play();
    if (mounted) setState(() => _controller = c);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return GestureDetector(
        onTap: _init,
        child: Container(
          height: 240, width: 180,
          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
          child: const Center(child: Icon(Icons.play_circle, size: 48, color: Colors.white)),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 200, child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
    );
  }
}
