import 'package:flutter/material.dart';

import '../profile/profile_repository.dart';

/// Discovery preferences editor. Returns true via Navigator.pop if saved.
class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key});
  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  final _repo = ProfileRepository();
  RangeValues _age = const RangeValues(18, 40);
  double _distance = 50;
  final Set<String> _interestedIn = {};
  bool _loading = true;

  static const _genders = {'male': 'Men', 'female': 'Women', 'nonbinary': 'Non-binary', 'other': 'Other'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _repo.myProfile();
    setState(() {
      _age = RangeValues((p['min_age'] as num).toDouble(), (p['max_age'] as num).toDouble());
      _distance = (p['max_distance_km'] as num).toDouble();
      _interestedIn.addAll((p['interested_in'] as List? ?? []).map((e) => e as String));
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _repo.savePreferences(
      interestedIn: _interestedIn.toList(),
      minAge: _age.start.round(),
      maxAge: _age.end.round(),
      maxDistanceKm: _distance.round(),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
    }
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('Show me'),
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
          const SizedBox(height: 12),
          Text('Age  ${_age.start.round()}–${_age.end.round()}'),
          RangeSlider(
            values: _age,
            min: 18, max: 80, divisions: 62,
            labels: RangeLabels('${_age.start.round()}', '${_age.end.round()}'),
            onChanged: (v) => setState(() => _age = v),
          ),
          Text('Maximum distance  ${_distance.round()} km'),
          Slider(
            value: _distance,
            min: 1, max: 500, divisions: 50,
            label: '${_distance.round()} km',
            onChanged: (v) => setState(() => _distance = v),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Apply')),
        ],
      ),
    );
  }
}
