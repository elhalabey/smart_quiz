import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'core/session/session_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final sessionManager = SessionManager();

  runApp(
    SmartQuizApp(
      sessionManager: sessionManager,
    ),
  );
}

class SmartQuizApp extends StatelessWidget {
  final SessionManager sessionManager;

  const SmartQuizApp({
    super.key,
    required this.sessionManager,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Quiz',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
        ),
        useMaterial3: true,
      ),
      home: AppRouter(
        sessionManager: sessionManager,
      ),
    );
  }
}


