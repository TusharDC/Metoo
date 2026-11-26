/// The caller's funnel position, from the `get_my_status()` RPC.
///
/// These are display values only. The server decides what is actually allowed —
/// see `0011_funnel.sql`. Never gate behaviour on these alone.
class UserStatus {
  final int swipesLeft;
  final int messagesLeft;
  final int matchesMade;
  final int credits;
  final DateTime? subscribedUntil;
  final bool isPaid;

  const UserStatus({
    required this.swipesLeft,
    required this.messagesLeft,
    required this.matchesMade,
    required this.credits,
    required this.subscribedUntil,
    required this.isPaid,
  });

  factory UserStatus.fromJson(Map<String, dynamic> j) => UserStatus(
        swipesLeft: (j['swipes_left'] as num?)?.toInt() ?? 0,
        messagesLeft: (j['messages_left'] as num?)?.toInt() ?? 0,
        matchesMade: (j['matches_made'] as num?)?.toInt() ?? 0,
        credits: (j['credits'] as num?)?.toInt() ?? 0,
        subscribedUntil: j['subscribed_until'] == null
            ? null
            : DateTime.tryParse(j['subscribed_until'] as String),
        isPaid: j['is_paid'] as bool? ?? false,
      );

  /// Paid users see no counter at all.
  bool get showSwipeCounter => !isPaid;
  bool get showMessageCounter => !isPaid;
}

/// Result of an `ai_swipe()` call.
class SwipeOutcome {
  /// A match was queued; it reveals in the Matches tab after the delay.
  final bool queued;

  /// The server refused — out of free swipes.
  final bool blocked;
  final String? reason;
  final int swipesLeft;

  const SwipeOutcome({
    required this.queued,
    required this.blocked,
    required this.reason,
    required this.swipesLeft,
  });

  factory SwipeOutcome.fromJson(Map<String, dynamic> j) => SwipeOutcome(
        queued: j['queued'] as bool? ?? false,
        blocked: j['blocked'] as bool? ?? false,
        reason: j['reason'] as String?,
        swipesLeft: (j['swipes_left'] as num?)?.toInt() ?? 0,
      );
}

/// Thrown when the server returns 402 from `ai-chat`.
class OutOfMessagesException implements Exception {
  final String reason;
  const OutOfMessagesException(this.reason);
  @override
  String toString() => 'OutOfMessagesException($reason)';
}
