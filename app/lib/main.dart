import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/auth/auth_service.dart';
import 'services/clip_store.dart';
import 'services/debug_log.dart';
import 'services/sync/backfill_queue.dart';
import 'ui/screens/auth_gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On-device diagnostic log first, so it captures everything below (it also
  // routes debugPrint through itself).
  await DebugLog.instance.init();
  // A boxing timer is held in one hand or propped on the floor; rotating it
  // mid-round helps nobody.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]).ignore();
  // Backend must be ready before any screen that reads auth/session state.
  await AuthService.initialize();
  // Enforce the spec's 7-day clip retention on every launch. Fire-and-forget:
  // a failed sweep must never delay the app starting.
  ClipStore().sweepExpired().ignore();
  // Drain any rounds recorded offline / that failed to sync — once now, and
  // again whenever the user signs in.
  BackfillQueue.instance.process().ignore();
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedIn ||
        data.event == AuthChangeEvent.tokenRefreshed) {
      BackfillQueue.instance.process().ignore();
    }
  });
  runApp(const BoxingCoachApp());
}

class BoxingCoachApp extends StatelessWidget {
  const BoxingCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Boxing Coach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}
