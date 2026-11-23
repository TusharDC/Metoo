import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/profile_card.dart';
import '../../shared/widgets/app_image.dart';

/// "It's a match!" celebration overlay shown after a reciprocal like.
Future<void> showMatchDialog(BuildContext context, ProfileCard other, String conversationId) {
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
                    fontWeight: FontWeight.bold,
                    color: Theme.of(ctx).colorScheme.primary)),
            const SizedBox(height: 16),
            if (other.primaryPhotoUrl != null)
              CircleAvatar(
                radius: 54,
                backgroundImage: appImageProvider(other.primaryPhotoUrl!),
              ),
            const SizedBox(height: 12),
            Text('You and ${other.displayName} liked each other.',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/chat/$conversationId', extra: other);
              },
              child: const Text('Send a message'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep swiping')),
          ],
        ),
      ),
    ),
  );
}
