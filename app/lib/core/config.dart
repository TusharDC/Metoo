/// App configuration, supplied at build/run time via --dart-define so secrets
/// never live in source. Example:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Offline UI-review build: no Supabase project, no auth, no LLM. Every
  /// repository serves canned data from `core/demo/`. Turn on with
  ///   flutter build apk --dart-define=DEMO=true
  /// Never ship this to a store — it bypasses login and the 18+ gate.
  static const demo = bool.fromEnvironment('DEMO');

  static bool get isConfigured =>
      demo || (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty);
}
