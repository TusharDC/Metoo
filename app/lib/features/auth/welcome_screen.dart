import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';

/// Entry screen: email + password sign-in or sign-up.
///
/// Deliberately not OTP. Phone OTP needs a paid SMS provider, and Supabase's
/// default email template sends a magic *link* rather than a code, so the old
/// 6-digit screen could never be satisfied. Password auth needs neither.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = true;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || !email.contains('@')) {
      return _snack('Enter a valid email address.');
    }
    if (password.length < 6) {
      return _snack('Password must be at least 6 characters.');
    }

    setState(() => _loading = true);
    try {
      if (_signUp) {
        final res = await Db.auth.signUp(email: email, password: password);
        // With "Confirm email" on there is a user but no session yet.
        if (res.session == null && mounted) {
          _snack('Check your email to confirm your account, then sign in.');
          setState(() => _signUp = false);
        }
      } else {
        await Db.auth.signInWithPassword(email: email, password: password);
      }
      // On success the session changes, AppSession notices, and the router
      // redirects to onboarding or the deck.
    } on AuthException catch (e) {
      _snack(_friendly(e.message));
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendly(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('already registered')) {
      return 'That email already has an account — try signing in.';
    }
    if (m.contains('invalid login')) return 'Wrong email or password.';
    if (m.contains('not confirmed')) {
      return 'Confirm your email first — check your inbox.';
    }
    return raw;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.favorite_rounded, size: 72, color: cs.primary),
                const SizedBox(height: 12),
                Text('Shararat',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.primary)),
                const SizedBox(height: 4),
                Text('A little flirting. A lot of Shararat.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 40),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Password (6+ characters)',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_signUp ? 'Create account' : 'Sign in'),
                ),
                TextButton(
                  onPressed:
                      _loading ? null : () => setState(() => _signUp = !_signUp),
                  child: Text(_signUp
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account'),
                ),
                const SizedBox(height: 20),
                Text(
                  'By continuing you confirm you are 18+ and agree to our '
                  'Terms & Privacy Policy. Companions are AI characters, '
                  'not real people.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
