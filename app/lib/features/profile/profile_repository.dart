import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/demo/demo_data.dart';
import '../../core/demo/demo_store.dart';
import '../../core/supabase.dart';

/// All profile reads/writes go through the server RPCs so the client never
/// touches enums/arrays/geography directly.
class ProfileRepository {
  Future<void> saveProfile({
    required String displayName,
    required DateTime dateOfBirth,
    required String gender,
    String? bio,
    List<String> interestedIn = const [],
    int minAge = 18,
    int maxAge = 60,
    int maxDistanceKm = 50,
    bool complete = false,
  }) async {
    if (AppConfig.demo) {
      return DemoStore.instance.saveProfile(displayName: displayName, bio: bio);
    }
    await Db.client.rpc('save_profile', params: {
      'p_display_name': displayName,
      'p_date_of_birth': dateOfBirth.toIso8601String().substring(0, 10),
      'p_gender': gender,
      'p_bio': bio,
      'p_interested_in': interestedIn,
      'p_min_age': minAge,
      'p_max_age': maxAge,
      'p_max_distance_km': maxDistanceKm,
      'p_complete': complete,
    });
  }

  Future<void> savePreferences({
    required List<String> interestedIn,
    required int minAge,
    required int maxAge,
    required int maxDistanceKm,
  }) =>
      Db.client.rpc('save_preferences', params: {
        'p_interested_in': interestedIn,
        'p_min_age': minAge,
        'p_max_age': maxAge,
        'p_max_distance_km': maxDistanceKm,
      });

  Future<void> setLocation(double lat, double lng, {String? city}) async {
    if (AppConfig.demo) return;
    await Db.client.rpc('set_my_location',
        params: {'p_lat': lat, 'p_lng': lng, 'p_city': city});
  }

  Future<void> setInterests(List<String> slugs) async {
    if (AppConfig.demo) return DemoStore.instance.setInterests(slugs);
    await Db.client.rpc('set_my_interests', params: {'p_slugs': slugs});
  }

  Future<Map<String, dynamic>> myProfile() async {
    if (AppConfig.demo) return DemoStore.instance.myProfile();
    return (await Db.client.rpc('get_my_profile')) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> card(String id) async =>
      (await Db.client.rpc('get_profile', params: {'target': id})) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> allInterests() async {
    if (AppConfig.demo) return demoInterests();
    final rows = await Db.client.from('interests').select('slug, label').order('label');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Upload a photo to the public `photos` bucket under {uid}/ and record it.
  /// Uses bytes so it works on web and mobile alike.
  Future<void> addPhoto(XFile file, int position) async {
    if (AppConfig.demo) return;
    final uid = Db.uid!;
    final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$position.$ext';
    final bytes = await file.readAsBytes();
    await Db.client.storage.from('photos').uploadBinary(
          path, bytes,
          fileOptions: FileOptions(contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}'),
        );
    await Db.client.from('profile_photos').insert({
      'profile_id': uid,
      'storage_path': path,
      'position': position,
    });
  }

  Future<void> removePhoto(String photoId, String storagePath) async {
    if (AppConfig.demo) return;
    await Db.client.storage.from('photos').remove([storagePath]);
    await Db.client.from('profile_photos').delete().eq('id', photoId);
  }

  Future<void> setDiscoverable(bool value) async {
    if (AppConfig.demo) return DemoStore.instance.setSetting('is_discoverable', value);
    await Db.client.from('profiles').update({'is_discoverable': value}).eq('id', Db.uid!);
  }
}
