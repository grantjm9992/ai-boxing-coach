import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/auth/auth_service.dart';
import 'services/clip_store.dart';
import 'ui/screens/auth_gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
