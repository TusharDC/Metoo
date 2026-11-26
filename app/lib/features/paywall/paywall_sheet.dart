import 'package:flutter/material.dart';

/// Shown when the server refuses a swipe or a message because the free
/// allowance is spent.
///
/// No payment provider is wired up yet: `grant_entitlement()` on the backend is
/// provider-agnostic and waits for a webhook, so this collects intent only.
/// When Razorpay / Play Billing / Stripe is chosen, replace [_onBuy].
enum PaywallReason { outOfSwipes, outOfMessages, dailyCap }

Future<void> showPaywall(
  BuildContext context, {
  required PaywallReason reason,
  String? characterName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PaywallSheet(reason: reason, characterName: characterName),
  );
}

class _PaywallSheet extends StatelessWidget {
  final PaywallReason reason;
  final String? characterName;
  const _PaywallSheet({required this.reason, this.characterName});

  String get _title => switch (reason) {
        PaywallReason.outOfSwipes => "You're out of swipes",
        PaywallReason.outOfMessages => characterName == null
            ? 'Keep the conversation going'
            : '$characterName is waiting…',
        PaywallReason.dailyCap => "That's enough for today",
      };

  String get _body => switch (reason) {
        PaywallReason.outOfSwipes =>
          'You used your 10 free swipes. Unlock more to keep meeting new people.',
        PaywallReason.outOfMessages =>
          'You used your 10 free messages. Unlock more to keep talking.',
        PaywallReason.dailyCap =>
          "You've hit today's limit. Come back tomorrow — she'll still be here.",
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canBuy = reason != PaywallReason.dailyCap;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            reason == PaywallReason.outOfMessages
                ? Icons.favorite
                : Icons.local_fire_department,
            size: 48,
            color: cs.primary,
          ),
          const SizedBox(height: 12),
          Text(_title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          if (canBuy) ...[
            _PackTile(
              label: '100 messages',
              price: '₹99',
              highlight: true,
              onTap: () => _onBuy(context, 'credits_100'),
            ),
            const SizedBox(height: 10),
            _PackTile(
              label: 'Unlimited for a month',
              price: '₹499',
              onTap: () => _onBuy(context, 'sub_monthly'),
            ),
            const SizedBox(height: 16),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(canBuy ? 'Maybe later' : 'OK'),
          ),
        ],
      ),
    );
  }

  void _onBuy(BuildContext context, String sku) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Payments are not switched on yet — coming soon.'),
      ));
  }
}

class _PackTile extends StatelessWidget {
  final String label;
  final String price;
  final bool highlight;
  final VoidCallback onTap;
  const _PackTile({
    required this.label,
    required this.price,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: highlight ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Text(price,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: cs.primary)),
            ],
          ),
        ),
      ),
    );
  }
}
