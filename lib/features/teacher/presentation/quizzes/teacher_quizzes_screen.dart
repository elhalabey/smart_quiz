import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'edit_teacher_quiz_screen.dart';
import '../../../../core/session/session_manager.dart';
import 'add_teacher_quiz_screen.dart';
import 'teacher_questions_screen.dart';

class TeacherQuizzesScreen extends StatelessWidget {
  final SessionManager sessionManager;

  const TeacherQuizzesScreen({
    super.key,
    required this.sessionManager,
  });

  String _statusText(String status) {
    switch (status) {
      case 'draft':
        return 'مسودة';
      case 'published':
        return 'منشور';
      case 'closed':
        return 'مغلق';
      case 'archived':
        return 'مؤرشف';
      default:
        return status;
    }
  }

  Color _statusColor(
    BuildContext context,
    String status,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (status) {
      case 'published':
        return colorScheme.primary;
      case 'closed':
        return colorScheme.error;
      case 'archived':
        return colorScheme.outline;
      case 'draft':
      default:
        return colorScheme.secondary;
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) {
      return 'غير محدد';
    }

    final date = timestamp.toDate();

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year - $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = sessionManager.currentSession?.uid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'اختباراتي',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: teacherId == null
            ? const Center(
                child: Text(
                  'لم يتم العثور على بيانات المعلم',
                ),
              )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('quizzes')
                    .where(
                      'teacherId',
                      isEqualTo: teacherId,
                    )
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _buildErrorState(
                      context,
                      snapshot.error.toString(),
                    );
                  }

                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final quizzes = [
                    ...(snapshot.data?.docs ?? <QueryDocumentSnapshot<
                        Map<String, dynamic>>>[]),
                  ];

                  quizzes.sort((a, b) {
                    final aCreatedAt =
                        a.data()['createdAt'] as Timestamp?;
                    final bCreatedAt =
                        b.data()['createdAt'] as Timestamp?;

                    if (aCreatedAt == null &&
                        bCreatedAt == null) {
                      return 0;
                    }

                    if (aCreatedAt == null) {
                      return 1;
                    }

                    if (bCreatedAt == null) {
                      return -1;
                    }

                    return bCreatedAt.compareTo(aCreatedAt);
                  });

                  if (quizzes.isEmpty) {
                    return _buildEmptyState(context);
                  }

                  return _buildQuizzesList(
                    context,
                    quizzes,
                  );
                },
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddTeacherQuizScreen(
                  sessionManager: sessionManager,
                ),
              ),
            );
          },
          icon: const Icon(
            Icons.add,
          ),
          label: const Text(
            'إضافة اختبار',
          ),
        ),
      ),
    );
  }

  Widget _buildQuizzesList(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> quizzes,
  ) {
    return FutureBuilder<
        Map<String, Map<String, dynamic>>>(
      future: _loadLookups(quizzes),
      builder: (context, lookupSnapshot) {
        if (lookupSnapshot.hasError) {
          return _buildErrorState(
            context,
            lookupSnapshot.error.toString(),
          );
        }

        if (lookupSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final lookups = lookupSnapshot.data ??
            <String, Map<String, dynamic>>{};

        final subjects =
            lookups['subjects'] ?? <String, dynamic>{};

        final classes =
            lookups['classes'] ?? <String, dynamic>{};

        final quizClasses =
            lookups['quizClasses'] ?? <String, dynamic>{};

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: quizzes.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = quizzes[index];
            final data = doc.data();

            return _buildQuizCard(
              context,
              doc.id,
              data,
              subjects,
              classes,
              quizClasses,
            );
          },
        );
      },
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadLookups(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> quizzes,
  ) async {
    final firestore = FirebaseFirestore.instance;

    final results = await Future.wait<
        QuerySnapshot<Map<String, dynamic>>>([
      firestore.collection('subjects').get(),
      firestore.collection('classes').get(),
      ...quizzes.map(
        (quiz) => firestore
            .collection('quizClasses')
            .where(
              'quizId',
              isEqualTo: quiz.id,
            )
            .get(),
      ),
    ]);

    final subjectsSnapshot = results[0];
    final classesSnapshot = results[1];

    final subjects = <String, dynamic>{};
    final classes = <String, dynamic>{};
    final quizClasses = <String, dynamic>{};

    for (final doc in subjectsSnapshot.docs) {
      subjects[doc.id] = doc.data();
    }

    for (final doc in classesSnapshot.docs) {
      classes[doc.id] = doc.data();
    }

    for (var index = 0;
        index < quizzes.length;
        index++) {
      final quiz = quizzes[index];
      final quizClassesSnapshot = results[index + 2];

      final classIds = <String>[];

      for (final doc in quizClassesSnapshot.docs) {
        final data = doc.data();
        final classId = data['classId'] as String?;

        if (classId != null) {
          classIds.add(classId);
        }
      }

      quizClasses[quiz.id] = classIds;
    }

    return {
      'subjects': subjects,
      'classes': classes,
      'quizClasses': quizClasses,
    };
  }

  Widget _buildQuizCard(
    BuildContext context,
    String quizId,
    Map<String, dynamic> data,
    Map<String, dynamic> subjects,
    Map<String, dynamic> classes,
    Map<String, dynamic> quizClasses,
  ) {
    final title =
        data['title'] as String? ?? 'بدون عنوان';

    final description =
        data['description'] as String? ?? '';

    final status =
        data['status'] as String? ?? 'draft';

    final subjectId =
        data['subjectId'] as String? ?? '';

    final startAt =
        data['startAt'] as Timestamp?;

    final endAt =
        data['endAt'] as Timestamp?;

    final subjectData =
        subjects[subjectId] as Map<String, dynamic>?;

    final subjectName =
        subjectData?['nameAr'] as String? ??
            subjectData?['name'] as String? ??
            'غير محددة';

    final classIds =
        quizClasses[quizId] as List<dynamic>? ?? [];

    final classNames = <String>[];

    for (final classId in classIds) {
      final classData =
          classes[classId] as Map<String, dynamic>?;

      if (classData == null) {
        continue;
      }

      final className =
          classData['name'] as String? ?? '';

      if (className.isNotEmpty) {
        classNames.add(className);
      }
    }

    final statusColor = _statusColor(
      context,
      status,
    );

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _showQuizActions(
            context,
            quizId,
            data,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusText(status),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  description,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildInfoRow(
                context,
                Icons.menu_book_outlined,
                'المادة',
                subjectName,
              ),
              const SizedBox(height: 6),
              _buildInfoRow(
                context,
                Icons.groups_outlined,
                'الفصول',
                classNames.isEmpty
                    ? 'غير محددة'
                    : classNames.join(' • '),
              ),
              const SizedBox(height: 6),
              _buildInfoRow(
                context,
                Icons.play_arrow_outlined,
                'البداية',
                _formatDate(startAt),
              ),
              const SizedBox(height: 6),
              _buildInfoRow(
                context,
                Icons.stop_outlined,
                'النهاية',
                _formatDate(endAt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context)
              .colorScheme
              .primary,
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 72,
              color: Theme.of(context)
                  .colorScheme
                  .outline,
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد اختبارات حتى الآن',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'يمكنك إنشاء اختبار جديد من زر إضافة اختبار.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    String error,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .error,
            ),
            const SizedBox(height: 16),
            const Text(
              'حدث خطأ أثناء تحميل الاختبارات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showQuizActions(
    BuildContext context,
    String quizId,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Wrap(
              children: [
                ListTile(
  leading: const Icon(
    Icons.edit_outlined,
  ),
  title: const Text(
    'تعديل الاختبار',
  ),
  onTap: () {
    Navigator.of(sheetContext).pop();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditTeacherQuizScreen(
          sessionManager: sessionManager,
          quizId: quizId,
          quizData: data,
        ),
      ),
    );
  },
),
                ListTile(
  leading: const Icon(
    Icons.quiz_outlined,
  ),
  title: const Text(
    'إدارة الأسئلة',
  ),
  onTap: () {
    Navigator.of(sheetContext).pop();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherQuestionsScreen(
          sessionManager: sessionManager,
          quizId: quizId,
          quizTitle:
              data['title']?.toString() ?? 'اختبار',
          subjectId:
              data['subjectId']?.toString() ?? '',
        ),
      ),
    );
  },
),
                ListTile(
                  leading: const Icon(
                    Icons.close_outlined,
                  ),
                  title: const Text(
                    'إغلاق',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
