import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/ai_character.dart';
import '../../shared/widgets/app_image.dart';

/// "It's a Match!" overlay after right-swiping an AI girl.
Future<void> showAiMatchDialog(BuildContext context, AiCharacter c, String conversationId) {
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("It's a match! 🎉",
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.primary)),
            const SizedBox(height: 16),
            if (c.avatarUrl != null)
              CircleAvatar(radius: 54, backgroundImage: appImageProvider(c.avatarUrl!))
            else
              CircleAvatar(radius: 54, child: Text(c.name[0], style: const TextStyle(fontSize: 32))),
            const SizedBox(height: 12),
            Text('${c.name} liked you back 😏', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/ai-chat/$conversationId', extra: c);
              },
              child: const Text('Say hi'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep swiping')),
          ],
        ),
      ),
    ),
  );
}
