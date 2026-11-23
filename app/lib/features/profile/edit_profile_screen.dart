import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase.dart';
import 'profile_repository.dart';

/// Edit display name, bio, interests, photos, and discoverability.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _repo = ProfileRepository();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final Set<String> _interests = {};
  List<Map<String, dynamic>> _options = [];
  List<Map<String, dynamic>> _photos = [];
  DateTime _dob = DateTime(2000);
  String _gender = 'other';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.myProfile();
    _options = await _repo.allInterests();
    setState(() {
      _name.text = p['display_name'] as String;
      _bio.text = (p['bio'] as String?) ?? '';
      _dob = DateTime.parse(p['date_of_birth'] as String);
      _gender = p['gender'] as String;
      _interests.addAll((p['interests'] as List? ?? []).map((e) => e as String));
      _photos = (p['photos'] as List? ?? []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repo.saveProfile(
        displayName: _name.text.trim(),
        dateOfBirth: _dob,
        gender: _gender,
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
      );
      await _repo.setInterests(_interests.toList());
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await _repo.addPhoto(picked, _photos.length);
    await _load();
  }

  Future<void> _removePhoto(Map<String, dynamic> photo) async {
    await _repo.removePhoto(photo['id'] as String, photo['path'] as String);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Photos', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final ph in _photos)
                      Stack(fit: StackFit.expand, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(Db.photoUrl(ph['path'] as String), fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2, right: 2,
                          child: GestureDetector(
                            onTap: () => _removePhoto(ph),
                            child: const CircleAvatar(radius: 12, child: Icon(Icons.close, size: 14)),
                          ),
                        ),
                      ]),
                    if (_photos.length < 6)
                      InkWell(
                        onTap: _addPhoto,
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
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bio,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Bio'),
                ),
                const SizedBox(height: 8),
                const Text('Interests', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _options
                      .map((o) => FilterChip(
                            label: Text(o['label'] as String),
                            selected: _interests.contains(o['slug']),
                            onSelected: (s) => setState(() =>
                                s ? _interests.add(o['slug'] as String) : _interests.remove(o['slug'])),
                          ))
                      .toList(),
                ),
              ],
            ),
    );
  }
}
