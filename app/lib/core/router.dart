import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'session.dart';
import '../features/auth/welcome_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/chat/chat_room_screen.dart';
import '../features/companions/ai_chat_screen.dart';
import '../features/profile/profile_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/profile/edit_profile_screen.dart';

GoRouter buildRouter(AppSession session) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) {
      if (!session.ready) return null; // wait for bootstrap (splash shown)
      final loc = state.matchedLocation;
      final authRoutes = loc == '/welcome' || loc == '/otp';

      if (!session.signedIn) {
        return authRoutes ? null : '/welcome';
      }
      // signed in but hasn't finished onboarding
      if (!session.onboardingComplete) {
        return loc == '/onboarding' ? null : '/onboarding';
      }
      // signed in + onboarded; keep them out of auth/onboarding screens
      if (authRoutes || loc == '/onboarding' || loc == '/') {
        return '/discover';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _Splash()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, s) => OtpScreen(args: s.extra as OtpArgs),
      ),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

      // main tabbed app
      GoRoute(path: '/discover', builder: (_, __) => const HomeShell(tab: 0)),
      GoRoute(path: '/likes', builder: (_, __) => const HomeShell(tab: 1)),
      GoRoute(path: '/companions', builder: (_, __) => const HomeShell(tab: 2)),
      GoRoute(path: '/chats', builder: (_, __) => const HomeShell(tab: 3)),
      GoRoute(path: '/me', builder: (_, __) => const HomeShell(tab: 4)),

      // pushed routes
      GoRoute(
        path: '/chat/:conversationId',
        builder: (_, s) => ChatRoomScreen(
          conversationId: s.pathParameters['conversationId']!,
          other: s.extra as dynamic,
        ),
      ),
      GoRoute(
        path: '/ai-chat/:conversationId',
        builder: (_, s) => AiChatScreen(
          conversationId: s.pathParameters['conversationId']!,
          character: s.extra as dynamic,
        ),
      ),
      GoRoute(
        path: '/profile/:id',
        builder: (_, s) => ProfileDetailScreen(profileId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/edit-profile', builder: (_, __) => const EditProfileScreen()),
    ],
  );
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
