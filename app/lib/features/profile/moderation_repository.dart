import '../../core/supabase.dart';

class ModerationRepository {
  Future<void> block(String targetId) =>
      Db.client.rpc('block_user', params: {'target': targetId});

  Future<void> report(String targetId, String reason, {String? details}) =>
      Db.client.rpc('report_user',
          params: {'target': targetId, 'p_reason': reason, 'p_details': details});

  static const reasons = [
    'Inappropriate photos',
    'Harassment or hate speech',
    'Spam or scam',
    'Fake profile',
    'Underage',
    'Something else',
  ];
}
