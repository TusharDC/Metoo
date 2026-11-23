import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';

class OtpArgs {
  final String identifier;
  final bool isPhone;
  const OtpArgs({required this.identifier, required this.isPhone});
}

/// Verifies the 6-digit OTP. On success, the router redirect takes over
/// (→ onboarding for new users, → discover for returning users).
class OtpScreen extends StatefulWidget {
  final OtpArgs args;
  const OtpScreen({super.key, required this.args});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final token = _code.text.trim();
    if (token.length < 4) return;
    setState(() => _loading = true);
    try {
      await Db.auth.verifyOTP(
        token: token,
        type: widget.args.isPhone ? OtpType.sms : OtpType.email,
        phone: widget.args.isPhone ? widget.args.identifier : null,
        email: widget.args.isPhone ? null : widget.args.identifier,
      );
      // AppSession picks up the auth change and the router redirects.
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Invalid or expired code.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      if (widget.args.isPhone) {
        await Db.auth.signInWithOtp(phone: widget.args.identifier);
      } else {
        await Db.auth.signInWithOtp(email: widget.args.identifier);
      }
      _snack('Code resent.');
    } catch (_) {
      _snack('Could not resend code.');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text('Enter the code sent to\n${widget.args.identifier}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: const TextStyle(fontSize: 28, letterSpacing: 8),
              decoration: const InputDecoration(counterText: '', hintText: '––––––'),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Verify'),
            ),
            TextButton(onPressed: _resend, child: const Text('Resend code')),
          ],
        ),
      ),
    );
  }
}
