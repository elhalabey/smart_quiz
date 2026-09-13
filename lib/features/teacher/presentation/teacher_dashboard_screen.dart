import 'package:flutter/material.dart';

import '../../../core/session/session_manager.dart';
import 'quizzes/teacher_quizzes_screen.dart';
import 'lessons/teacher_lessons_screen.dart';
import 'results/teacher_results_screen.dart';
import 'questions/teacher_question_bank_screen.dart';

class TeacherDashboardScreen extends StatelessWidget {
  final SessionManager sessionManager;

  const TeacherDashboardScreen({
    super.key,
    required this.sessionManager,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'لوحة المعلم',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWelcomeCard(
                  colorScheme,
                ),
                const SizedBox(height: 24),
                const Text(
                  'إدارة التعليم',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildMenuGrid(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: colorScheme.primary,
              child: Icon(
                Icons.person_outline,
                size: 32,
                color: colorScheme.onPrimary,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مرحبًا بك',
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'المعلم',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuGrid(BuildContext context) {
    final items = [
      _DashboardItem(
  title: 'الاختبارات',
  icon: Icons.assignment_outlined,
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherQuizzesScreen(
          sessionManager: sessionManager,
        ),
      ),
    );
  },
),
      _DashboardItem(
        title: 'الأسئلة',
        icon: Icons.quiz_outlined,
        onTap: () {    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherQuestionBankScreen(),
      ),
    );
    },
      ),
      _DashboardItem(
        title: 'الطلاب',
        icon: Icons.school_outlined,
        onTap: () {},
      ),
      _DashboardItem(
        title: 'النتائج',
        icon: Icons.bar_chart_outlined,
        onTap: () {    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherResultsScreen(
          sessionManager: sessionManager,
        ),
      ),
    );
    },
      ),
      _DashboardItem(
        title: 'الدروس',
        icon: Icons.menu_book_outlined,
        onTap: () {   Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherLessonsScreen(
          sessionManager: sessionManager,
        ),
      ),
    );},
      ),
      _DashboardItem(
        title: 'الفصول والمجموعات',
        icon: Icons.groups_outlined,
        onTap: () {},
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, index) {
        return _buildDashboardCard(
          context,
          items[index],
        );
      },
    );
  }

  Widget _buildDashboardCard(
    BuildContext context,
    _DashboardItem item,
  ) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 42,
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _DashboardItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });
}
