import '../../core/supabase.dart';

/// A sanitized profile as returned by the server RPCs (build_profile_card):
/// age (not DOB), coarse distance (not exact geo), ordered photos, interests.
class ProfileCard {
  final String id;
  final String displayName;
  final int age;
  final String gender;
  final String? bio;
  final String? city;
  final bool isVerified;
  final double? distanceKm;
  final List<String> photoPaths; // ordered, [0] = primary
  final List<String> interests;

  ProfileCard({
    required this.id,
    required this.displayName,
    required this.age,
    required this.gender,
    required this.bio,
    required this.city,
    required this.isVerified,
    required this.distanceKm,
    required this.photoPaths,
    required this.interests,
  });

  factory ProfileCard.fromJson(Map<String, dynamic> j) {
    final photos = (j['photos'] as List? ?? [])
        .map((e) => (e as Map)['path'] as String)
        .toList();
    return ProfileCard(
      id: j['id'] as String,
      displayName: j['display_name'] as String,
      age: (j['age'] as num).toInt(),
      gender: j['gender'] as String,
      bio: j['bio'] as String?,
      city: j['city'] as String?,
      isVerified: j['is_verified'] as bool? ?? false,
      distanceKm: (j['distance_km'] as num?)?.toDouble(),
      photoPaths: photos,
      interests: (j['interests'] as List? ?? []).map((e) => e as String).toList(),
    );
  }

  String? get primaryPhotoUrl =>
      photoPaths.isEmpty ? null : Db.photoUrl(photoPaths.first);

  List<String> get photoUrls => photoPaths.map(Db.photoUrl).toList();

  String get distanceLabel =>
      distanceKm == null ? '' : '${distanceKm!.round()} km away';
}
