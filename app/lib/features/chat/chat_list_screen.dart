import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../shared/models/conversation_summary.dart';
import '../../shared/widgets/app_image.dart';
import 'chat_repository.dart';

final _conversationsProvider =
    FutureProvider.autoDispose<List<ConversationSummary>>((ref) => ChatRepository().conversations());

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_conversationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_conversationsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (convos) {
            if (convos.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 140),
                Icon(Icons.chat_bubble_outline, size: 56),
                SizedBox(height: 12),
                Center(child: Text('No chats yet.\nMatch with someone to start talking.',
                    textAlign: TextAlign.center)),
              ]);
            }
            return ListView.separated(
              itemCount: convos.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
              itemBuilder: (_, i) => _Tile(
                convo: convos[i],
                onReturn: () => ref.invalidate(_conversationsProvider),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final ConversationSummary convo;
  final VoidCallback onReturn;
  const _Tile({required this.convo, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final url = convo.other.primaryPhotoUrl;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 28,
        backgroundImage: url != null ? appImageProvider(url) : null,
        child: url == null ? const Icon(Icons.person) : null,
      ),
      title: Text(convo.other.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(convo.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (convo.lastMessageAt != null)
            Text(DateFormat.Hm().format(convo.lastMessageAt!.toLocal()),
                style: Theme.of(context).textTheme.bodySmall),
          if (convo.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
              child: Text('${convo.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
        ],
      ),
      onTap: () async {
        await context.push('/chat/${convo.conversationId}', extra: convo.other);
        onReturn();
      },
    );
  }
}
