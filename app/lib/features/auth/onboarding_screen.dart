import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../profile/profile_repository.dart';

/// Multi-step onboarding. On finish, writes the profile (complete=true),
/// uploads photos, interests, and location, then flips session state.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _repo = ProfileRepository();
  final _page = PageController();
  int _step = 0;
  bool _saving = false;

  // collected data
  final _name = TextEditingController();
  DateTime? _dob;
  String? _gender;
  final Set<String> _interestedIn = {};
  final _bio = TextEditingController();
  final Set<String> _interests = {};
  final List<XFile> _photos = [];
  List<Map<String, dynamic>> _interestOptions = [];

  static const _genders = {'male': 'Man', 'female': 'Woman', 'nonbinary': 'Non-binary', 'other': 'Other'};

  @override
  void initState() {
    super.initState();
    _repo.allInterests().then((v) => setState(() => _interestOptions = v));
  }

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _canAdvance => switch (_step) {
        0 => _name.text.trim().isNotEmpty && _dob != null,
        1 => _gender != null && _interestedIn.isNotEmpty,
        2 => _photos.isNotEmpty,
        _ => true,
      };

  Future<void> _next() async {
    if (_step < 3) {
      setState(() => _step++);
      _page.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await _repo.saveProfile(
        displayName: _name.text.trim(),
        dateOfBirth: _dob!,
        gender: _gender!,
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        interestedIn: _interestedIn.toList(),
        complete: true,
      );
      for (var i = 0; i < _photos.length; i++) {
        await _repo.addPhoto(_photos[i], i);
      }
      if (_interests.isNotEmpty) await _repo.setInterests(_interests.toList());
      await _captureLocation();
      ref.read(sessionProvider).markOnboardingComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not finish setup: $e')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _captureLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      await _repo.setLocation(pos.latitude, pos.longitude);
    } catch (_) {/* location is optional */}
  }

  Future<void> _pickPhotos() async {
    final picked = await ImagePicker().pickMultiImage(limit: 6);
    if (picked.isEmpty) return;
    setState(() {
      for (final p in picked) {
        if (_photos.length < 6) _photos.add(p);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Set up your profile  ${_step + 1}/4'),
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_step + 1) / 4),
        ),
      ),
      body: PageView(
        controller: _page,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _basicsStep(),
          _genderStep(),
          _photosStep(),
          _bioStep(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: (!_canAdvance || _saving) ? null : _next,
            child: _saving
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_step == 3 ? 'Finish' : 'Continue'),
          ),
        ),
      ),
    );
  }

  Widget _pad(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.all(24), child: child);

  Widget _basicsStep() => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('What should we call you?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'First name'),
          ),
          const SizedBox(height: 24),
          const Text('Your birthday', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.cake_outlined),
            label: Text(_dob == null ? 'Select date' : DateFormat.yMMMMd().format(_dob!)),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime(now.year - 20),
                firstDate: DateTime(now.year - 100),
                lastDate: DateTime(now.year - 18, now.month, now.day),
                helpText: 'You must be 18 or older',
              );
              if (d != null) setState(() => _dob = d);
            },
          ),
        ],
      ));

  Widget _genderStep() => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('I am a', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
          const SizedBox(height: 28),
          const Text('Show me', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _genders.entries
                .map((e) => FilterChip(
                      label: Text(e.value),
                      selected: _interestedIn.contains(e.key),
                      onSelected: (s) => setState(() =>
                          s ? _interestedIn.add(e.key) : _interestedIn.remove(e.key)),
                    ))
                .toList(),
          ),
        ],
      ));

  Widget _photosStep() => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add your photos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('First photo is your main one. Up to 6.'),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < _photos.length; i++)
                Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb
                        ? Image.network(_photos[i].path, fit: BoxFit.cover)
                        : Image.file(File(_photos[i].path), fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2, right: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: const CircleAvatar(radius: 12, child: Icon(Icons.close, size: 14)),
                    ),
                  ),
                ]),
              if (_photos.length < 6)
                InkWell(
                  onTap: _pickPhotos,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined),
                  ),
                ),
            ],
          ),
        ],
      ));

  Widget _bioStep() => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About you', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _bio,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(hintText: 'Write a short bio…'),
          ),
          const SizedBox(height: 16),
          const Text('Interests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _interestOptions
                .map((o) => FilterChip(
                      label: Text(o['label'] as String),
                      selected: _interests.contains(o['slug']),
                      onSelected: (s) => setState(() =>
                          s ? _interests.add(o['slug'] as String) : _interests.remove(o['slug'])),
                    ))
                .toList(),
          ),
        ],
      ));
}
