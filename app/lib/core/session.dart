import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'supabase.dart';

/// Tracks auth + onboarding state and drives router redirects.
/// Exposed as a [Listenable] so go_router can refresh on change.
class AppSession extends ChangeNotifier {
  bool _ready = false;
  bool _signedIn = false;
  bool _onboardingComplete = false;

  bool get ready => _ready;
  bool get signedIn => _signedIn;
  bool get onboardingComplete => _onboardingComplete;

  AppSession() {
    if (AppConfig.demo) {
      // No auth client in demo builds: land straight on the main shell.
      _signedIn = true;
      _onboardingComplete = true;
      _ready = true;
      return;
    }
    _signedIn = Db.isSignedIn;
    Db.auth.onAuthStateChange.listen((data) async {
      _signedIn = data.session != null;
      if (_signedIn) {
        await _loadProfileState();
      } else {
        _onboardingComplete = false;
      }
      _ready = true;
      notifyListeners();
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_signedIn) await _loadProfileState();
    _ready = true;
    notifyListeners();
  }

  Future<void> _loadProfileState() async {
    try {
      final row = await Db.client
          .from('profiles')
          .select('onboarding_complete')
          .eq('id', Db.uid!)
          .maybeSingle();
      _onboardingComplete = (row?['onboarding_complete'] as bool?) ?? false;
    } on PostgrestException {
      _onboardingComplete = false;
    }
  }

  /// Called by onboarding when the profile is finalized.
  void markOnboardingComplete() {
    _onboardingComplete = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (AppConfig.demo) return;
    if (_signedIn) await _loadProfileState();
    notifyListeners();
  }
}
