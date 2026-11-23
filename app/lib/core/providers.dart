import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session.dart';

/// App-wide auth/onboarding session. Lives for the whole app.
final sessionProvider = ChangeNotifierProvider<AppSession>((ref) => AppSession());
