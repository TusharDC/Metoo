/// Static content for DEMO mode (see [AppConfig.demo]).
///
/// Mirrors `backend/scripts/roster.json` — the canonical 12-girl lineup — so the
/// app can be driven end-to-end with no Supabase project behind it. Avatar paths
/// are deliberately null: the UI falls back to the accent-colour gradient card,
/// which keeps the build fully offline.
library;

/// One character, in the shape `get_characters()` / `get_ai_discover_feed()`
/// return, so the real models parse it unchanged.
List<Map<String, dynamic>> demoCharacters() => [
      _c(1, 'aanya', 'Aanya', 23, 'Delhi', 'bubbly · flirty · foodie', '#FF6F61',
          'playful', ['cafe hopping', 'fashion', 'foodie']),
      _c(2, 'ishaa', 'Ishaa', 24, 'Mumbai', 'confident · sassy · ambitious', '#E74C3C',
          'mischievous', ['modeling', 'nightlife', 'ambition']),
      _c(3, 'riya', 'Riya', 22, 'Bengaluru', 'nerdy-cute · witty · curious', '#1ABC9C',
          'playful', ['tech', 'gaming', 'coffee']),
      _c(4, 'meera', 'Meera', 25, 'Chennai', 'graceful · soulful · calm', '#9B59B6',
          'slow burn', ['classical dance', 'poetry', 'art']),
      _c(5, 'simran', 'Simran', 23, 'Chandigarh', 'fun · warm · foodie', '#F39C12',
          'playful', ['bhangra', 'foodie', 'road trips']),
      _c(6, 'ananya', 'Ananya', 24, 'Kolkata', 'artsy · poetic · deep', '#6C7A89',
          'slow burn', ['art', 'poetry', 'rain']),
      _c(7, 'tara', 'Tara', 22, 'Goa', 'free-spirited · chill · adventurous', '#16A085',
          'playful', ['beach', 'surfing', 'music']),
      _c(8, 'naina', 'Naina', 25, 'Jaipur', 'elegant · poised · warm', '#C0392B',
          'slow burn', ['heritage', 'photography', 'tea']),
      _c(9, 'pari', 'Pari', 23, 'Lucknow', 'sweet · gentle · shy', '#F8A5C2',
          'slow burn', ['poetry', 'cooking', 'music']),
      _c(10, 'avni', 'Avni', 24, 'Ahmedabad', 'chirpy · driven · bubbly', '#E67E22',
          'playful', ['startup', 'dandiya', 'travel']),
      _c(11, 'kiara', 'Kiara', 22, 'Manipur', 'edgy · cool · indie', '#8E44AD',
          'mischievous', ['indie music', 'sneakers', 'art']),
      _c(12, 'sana', 'Sana', 24, 'Srinagar', 'mysterious · poetic · warm', '#2980B9',
          'slow burn', ['poetry', 'chai', 'mountains']),
    ];

Map<String, dynamic> _c(int id, String slug, String name, int age, String region,
        String personality, String accent, String mood, List<String> traits) =>
    {
      'id': id,
      'slug': slug,
      'name': name,
      'tagline': personality,
      'bio': '$age • $region',
      'personality': personality,
      'avatar_path': null,
      'accent_color': accent,
      'default_mood': mood,
      'traits': traits,
    };

/// Canned opener she sends when a match is first opened.
String demoOpener(String slug) => switch (slug) {
      'aanya' => 'heyy finally 😄 was starting to think you had no taste',
      'ishaa' => 'oh so you swiped right. bold.',
      'riya' => 'hi!! ok quick q — are you a cat person or do i leave now',
      'meera' => 'hello :) you caught me mid-chai',
      'simran' => 'oye hello! kya kar rahe ho',
      'ananya' => 'hi. it\'s raining here, perfect timing honestly',
      'tara' => 'heyyy! just got back from the beach, sandy and unbothered',
      'naina' => 'hello :) you have good timing, i was bored',
      'pari' => 'hi… 🙈 i wasn\'t sure if you\'d message',
      'avni' => 'hiii! ok tell me one interesting thing about you, go',
      'kiara' => 'sup. you look like you have bad music taste, prove me wrong',
      _ => 'hey :) you\'re up late',
    };

/// Rotating replies used by the demo chat engine. No LLM call is made.
const demoReplies = <String>[
  'haha stoppp 😭',
  'wait really? tell me more',
  'hmm i don\'t believe you',
  'ok that\'s actually kind of cute',
  'arre you\'re too much 😄',
  'i was literally thinking the same thing',
  'you\'re lucky i\'m in a good mood today',
  'mmm go on…',
  'nope. not falling for that 😏',
  'ok fine you win this one',
  'brb my mom is calling, don\'t go anywhere',
  'so what else. distract me, i\'m bored',
];

/// The signed-in user's own profile, as `get_my_profile()` shapes it.
Map<String, dynamic> demoMyProfile() => {
      'id': demoUserId,
      'display_name': 'Demo User',
      'date_of_birth': '1998-06-14',
      'age': 27,
      'gender': 'male',
      'bio': 'Running the Shararat demo build. Nothing here touches a server.',
      'interested_in': ['female'],
      'min_age': 18,
      'max_age': 35,
      'max_distance_km': 50,
      'city': 'Mumbai',
      'is_verified': false,
      'is_discoverable': true,
      'onboarding_complete': true,
      'photos': <Map<String, dynamic>>[],
      'interests': ['music', 'travel', 'tech'],
      'interest_labels': ['Music', 'Tech', 'Travel'],
    };

const demoUserId = '00000000-0000-4000-8000-000000000001';

/// Interest chips, as the `interests` table returns them.
List<Map<String, dynamic>> demoInterests() => const [
      {'slug': 'art', 'label': 'Art'},
      {'slug': 'coffee', 'label': 'Coffee'},
      {'slug': 'cooking', 'label': 'Cooking'},
      {'slug': 'dancing', 'label': 'Dancing'},
      {'slug': 'fashion', 'label': 'Fashion'},
      {'slug': 'fitness', 'label': 'Fitness'},
      {'slug': 'foodie', 'label': 'Foodie'},
      {'slug': 'gaming', 'label': 'Gaming'},
      {'slug': 'movies', 'label': 'Movies'},
      {'slug': 'music', 'label': 'Music'},
      {'slug': 'nature', 'label': 'Nature'},
      {'slug': 'nightlife', 'label': 'Nightlife'},
      {'slug': 'pets', 'label': 'Pets'},
      {'slug': 'photography', 'label': 'Photography'},
      {'slug': 'reading', 'label': 'Reading'},
      {'slug': 'tech', 'label': 'Tech'},
      {'slug': 'travel', 'label': 'Travel'},
      {'slug': 'yoga', 'label': 'Yoga'},
    ];

/// Notification / privacy toggles, as `user_settings` returns them.
Map<String, dynamic> demoSettings() => {
      'notify_messages': true,
      'notify_matches': true,
      'notify_likes': true,
      'notify_marketing': false,
      'show_online_status': true,
      'show_distance': true,
      'is_discoverable': true,
    };
