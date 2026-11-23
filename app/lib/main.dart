import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/supabase.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  // Demo builds never touch Supabase, so skip client init entirely.
  if (!AppConfig.demo) await Db.init();
  runApp(const ProviderScope(child: ShararatApp()));
}

class ShararatApp extends ConsumerWidget {
  const ShararatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final router = buildRouter(session);
    return MaterialApp.router(
      title: 'Shararat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
    );
  }
}

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Missing Supabase configuration.\n\nRun with:\n'
                'flutter run \\\n'
                '  --dart-define=SUPABASE_URL=... \\\n'
                '  --dart-define=SUPABASE_ANON_KEY=...',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
      );
}
