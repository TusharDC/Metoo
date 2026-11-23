import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import 'otp_screen.dart';

/// Entry screen: choose phone or email, request an OTP.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _usePhone = true;
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() => _loading = true);
    try {
      if (_usePhone) {
        await Db.auth.signInWithOtp(phone: value);
      } else {
        await Db.auth.signInWithOtp(email: value);
      }
      if (!mounted) return;
      context.push('/otp', extra: OtpArgs(identifier: value, isPhone: _usePhone));
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not send code. Check the number/email and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.favorite_rounded, size: 72, color: cs.primary),
              const SizedBox(height: 12),
              Text('Shararat',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: cs.primary)),
              const SizedBox(height: 4),
              Text('Meet. Match. Chat.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Phone'), icon: Icon(Icons.phone)),
                  ButtonSegment(value: false, label: Text('Email'), icon: Icon(Icons.email)),
                ],
                selected: {_usePhone},
                onSelectionChanged: (s) => setState(() {
                  _usePhone = s.first;
                  _controller.clear();
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                keyboardType: _usePhone ? TextInputType.phone : TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: _usePhone ? '+91 98765 43210' : 'you@example.com',
                  prefixIcon: Icon(_usePhone ? Icons.phone : Icons.email),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _continue,
                child: _loading
                    ? const SizedBox(
                        height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue'),
              ),
              const SizedBox(height: 16),
              Text(
                'By continuing you confirm you are 18+ and agree to our Terms & Privacy Policy.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
