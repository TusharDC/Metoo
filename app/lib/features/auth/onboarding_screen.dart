import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../profile/profile_repository.dart';

/// Minimal onboarding for an AI-companion product: name, date of birth, gender.
///
/// There is deliberately no photo upload and no "looking for" step. The user is
/// not being shown to anyone — the companions are app-authored — so a dating
/// profile would be friction with no payoff. Date of birth stays because the
/// 18+ gate is both a legal requirement and a check constraint on `profiles`.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _repo = ProfileRepository();
  final _name = TextEditingController();
  DateTime? _dob;
  String? _gender;
  bool _saving = false;

  static const _genders = {
    'male': 'Man',
    'female': 'Woman',
    'nonbinary': 'Non-binary',
    'other': 'Other',
  };

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canFinish =>
      _name.text.trim().isNotEmpty && _dob != null && _gender != null;

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await _repo.saveProfile(
        displayName: _name.text.trim(),
        dateOfBirth: _dob!,
        gender: _gender!,
        complete: true,
      );
      ref.read(sessionProvider).markOnboardingComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not finish setup: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tell us about you'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What should we call you?',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'First name'),
            ),
            const SizedBox(height: 28),
            Text('Your birthday',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('You must be 18 or older to use Shararat.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.cake_outlined),
              label: Text(_dob == null
                  ? 'Select date'
                  : DateFormat.yMMMMd().format(_dob!)),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime(now.year - 22),
                  firstDate: DateTime(now.year - 100),
                  lastDate: DateTime(now.year - 18, now.month, now.day),
                  helpText: 'You must be 18 or older',
                );
                if (d != null) setState(() => _dob = d);
              },
            ),
            const SizedBox(height: 28),
            Text('I am a',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _genders.entries
                  .map((e) => ChoiceChip(
                        label: Text(e.value),
                        selected: _gender == e.key,
                        onSelected: (_) => setState(() => _gender = e.key),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: (!_canFinish || _saving) ? null : _finish,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Start swiping'),
          ),
        ),
      ),
    );
  }
}
