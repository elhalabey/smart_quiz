import 'package:flutter/material.dart';

import '../session/session_manager.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/teacher/presentation/teacher_dashboard_screen.dart';
import '../../features/student/presentation/student_dashboard_screen.dart';
import '../../features/parent/presentation/parent_dashboard_screen.dart';

class AppRouter extends StatelessWidget {
  final SessionManager sessionManager;

  const AppRouter({
    super.key,
    required this.sessionManager,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessionManager,
      builder: (context, child) {
        final session = sessionManager.currentSession;

        if (session == null) {
          return LoginScreen(
            sessionManager: sessionManager,
          );
        }

        switch (session.role) {
          case 'admin':
            return const AdminDashboardScreen();

          case 'teacher':
            return TeacherDashboardScreen(
              sessionManager: sessionManager,
            );

          case 'student':
            return StudentDashboardScreen(
              sessionManager: sessionManager,
            );

          case 'parent':
            return const ParentDashboardScreen();

          default:
            sessionManager.clearSession();

            return LoginScreen(
              sessionManager: sessionManager,
            );
        }
      },
    );
  }
}
