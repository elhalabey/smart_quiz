import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_quiz_screen.dart';
import 'edit_quiz_screen.dart';
import '../questions/questions_screen.dart';

class QuizzesScreen extends StatelessWidget {
  const QuizzesScreen({super.key});

  String _statusLabel(String status) {
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
        return Colors.green;
      case 'closed':
        return Colors.orange;
      case 'archived':
        return Colors.grey;
      case 'draft':
      default:
        return colorScheme.primary;
    }
  }

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'غير محدد';
    }

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '$day/$month/${value.year}  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'الاختبارات',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('quizzes')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, quizSnapshot) {
            if (quizSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'حدث خطأ أثناء تحميل الاختبارات:\n'
                    '${quizSnapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (quizSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final quizzes = quizSnapshot.data?.docs ?? [];

            if (quizzes.isEmpty) {
              return const Center(
                child: Text(
                  'لا توجد اختبارات حتى الآن',
                  style: TextStyle(fontSize: 16),
                ),
              );
            }

            return FutureBuilder<_QuizLookups>(
              future: _loadLookups(),
              builder: (context, lookupSnapshot) {
                if (lookupSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (lookupSnapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'حدث خطأ أثناء تحميل بيانات المواد والمعلمين والفصول:\n'
                        '${lookupSnapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final lookups =
                    lookupSnapshot.data ??
                    const _QuizLookups.empty();

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: quizzes.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = quizzes[index];
                    final data = doc.data();

                    final title =
                        (data['title'] as String?)?.trim() ??
                        'بدون عنوان';

                    final description =
                        (data['description'] as String?)?.trim() ??
                        '';

                    final status =
                        (data['status'] as String?)?.trim() ??
                        'draft';

                    final subjectId =
                        (data['subjectId'] as String?)?.trim() ??
                        '';

                    final teacherId =
                        (data['teacherId'] as String?)?.trim() ??
                        '';

                    final startAt =
                        _readDateTime(data['startAt']);

                    final endAt =
                        _readDateTime(data['endAt']);

                    final subjectName =
                        lookups.subjectNames[subjectId] ??
                        'مادة غير معروفة';

                    final teacherName =
                        lookups.teacherNames[teacherId] ??
                        'معلم غير معروف';

                    final classNames =
                        lookups.quizClasses[doc.id] ?? [];

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: ListTile(
                          title: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (description.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 6,
                                    ),
                                    child: Text(
                                      description,
                                      maxLines: 2,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  ),
                                Text(
                                  'المادة: $subjectName',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'المعلم: $teacherName',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  classNames.isEmpty
                                      ? 'الفصول: لا توجد'
                                      : 'الفصول: ${classNames.join('، ')}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.play_circle_outline,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'البداية: ${_formatDateTime(startAt)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.stop_circle_outlined,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'النهاية: ${_formatDateTime(endAt)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(
                                      context,
                                      status,
                                    ).withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _statusLabel(status),
                                    style: TextStyle(
                                      color: _statusColor(
                                        context,
                                        status,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EditQuizScreen(
                                      quizId: doc.id,
                                      quizData: data,
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (value == 'questions') {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        QuestionsScreen(
                                      quizId: doc.id,
                                      quizTitle: title,
                                      quizData: data,
                                    ),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined),
                                    SizedBox(width: 10),
                                    Text('تعديل الاختبار'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'questions',
                                child: Row(
                                  children: [
                                    Icon(Icons.quiz_outlined),
                                    SizedBox(width: 10),
                                    Text('إدارة الأسئلة'),
                                  ],
                                ),
                              ),
                            ],
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.more_vert),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        floatingActionButton:
            FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AddQuizScreen(),
              ),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('إضافة اختبار'),
        ),
      ),
    );
  }

  Future<_QuizLookups> _loadLookups() async {
    final firestore = FirebaseFirestore.instance;

    final results = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
  firestore.collection('subjects').get(),
  firestore
      .collection('users')
      .where('role', isEqualTo: 'teacher')
      .where('active', isEqualTo: true)
      .get(),
  firestore.collection('classes').get(),
  firestore.collection('quizClasses').get(),
]);

    final subjectsSnapshot =
        results[0];

    final teachersSnapshot =
        results[1];

    final classesSnapshot =
        results[2];

    final quizClassesSnapshot =
        results[3];

    final subjectNames = <String, String>{};
    final teacherNames = <String, String>{};
    final classNames = <String, String>{};
    final quizClassIds = <String, List<String>>{};

    for (final doc in subjectsSnapshot.docs) {
      final data = doc.data();

      final nameAr =
          (data['nameAr'] as String?)?.trim() ?? '';

      final nameEn =
          (data['nameEn'] as String?)?.trim() ?? '';

      if (nameAr.isNotEmpty) {
        subjectNames[doc.id] = nameAr;
      } else if (nameEn.isNotEmpty) {
        subjectNames[doc.id] = nameEn;
      }
    }

    for (final doc in teachersSnapshot.docs) {
      final data = doc.data();

      final name =
          (data['name'] as String?)?.trim() ?? '';

      if (name.isNotEmpty) {
        teacherNames[doc.id] = name;
      }
    }

    for (final doc in classesSnapshot.docs) {
      final data = doc.data();

      final name =
          (data['name'] as String?)?.trim() ?? '';

      if (name.isNotEmpty) {
        classNames[doc.id] = name;
      }
    }

    for (final doc in quizClassesSnapshot.docs) {
      final data = doc.data();

      final quizId =
          (data['quizId'] as String?)?.trim() ?? '';

      final classId =
          (data['classId'] as String?)?.trim() ?? '';

      if (quizId.isEmpty || classId.isEmpty) {
        continue;
      }

      quizClassIds.putIfAbsent(
        quizId,
        () => [],
      ).add(classId);
    }

    final quizClasses = <String, List<String>>{};

    for (final entry in quizClassIds.entries) {
      quizClasses[entry.key] = entry.value
          .map(
            (classId) =>
                classNames[classId] ?? 'فصل غير معروف',
          )
          .toList();
    }

    return _QuizLookups(
      subjectNames: subjectNames,
      teacherNames: teacherNames,
      quizClasses: quizClasses,
    );
  }
}

class _QuizLookups {
  final Map<String, String> subjectNames;
  final Map<String, String> teacherNames;
  final Map<String, List<String>> quizClasses;

  const _QuizLookups({
    required this.subjectNames,
    required this.teacherNames,
    required this.quizClasses,
  });

  const _QuizLookups.empty()
      : subjectNames = const {},
        teacherNames = const {},
        quizClasses = const {};
}
