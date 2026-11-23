import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

/// Thin accessors over the global Supabase client.
class Db {
  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;

  static String? get uid => auth.currentUser?.id;
  static bool get isSignedIn => auth.currentSession != null;

  /// Public URL for a path in the public `photos` bucket.
  static String photoUrl(String path) =>
      client.storage.from('photos').getPublicUrl(path);

  /// Signed URL for a private chat-media attachment.
  static Future<String> chatMediaUrl(String path) =>
      client.storage.from('chat-media').createSignedUrl(path, 60 * 60);

  /// Signed URL for private AI-generated media (voice/photo/video).
  static Future<String> aiMediaUrl(String path) =>
      client.storage.from('ai-media').createSignedUrl(path, 60 * 60);

  static Future<void> init() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // Supabase renamed anonKey → publishableKey; the anon/publishable key
      // value is passed through unchanged.
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }
}
