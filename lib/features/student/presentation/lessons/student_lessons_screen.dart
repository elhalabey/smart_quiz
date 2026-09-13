import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';

class StudentLessonsScreen extends StatefulWidget {
  final SessionManager sessionManager;

  const StudentLessonsScreen({
    super.key,
    required this.sessionManager,
  });

  @override
  State<StudentLessonsScreen> createState() => _StudentLessonsScreenState();
}

class _StudentLessonsScreenState extends State<StudentLessonsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loadingSubjects = true;
  List<_StudentSubject> _subjects = [];
  String? _selectedSubjectId;

  @override
  void initState() {
    super.initState();
    _loadStudentSubjects();
  }

  Future<void> _loadStudentSubjects() async {
    if (mounted) {
      setState(() {
        _loadingSubjects = true;
      });
    }

    try {
      final studentId = widget.sessionManager.currentSession?.uid;

      if (studentId == null) {
        throw Exception('لم يتم العثور على جلسة الطالب.');
      }

      final studentSubjectsSnapshot = await _firestore
          .collection('studentSubjects')
          .where('studentId', isEqualTo: studentId)
          .get();

      final subjectIds = studentSubjectsSnapshot.docs
          .map((doc) => doc.data()['subjectId']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();

      if (subjectIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _subjects = [];
          _selectedSubjectId = null;
          _loadingSubjects = false;
        });
        return;
      }

      final subjectsSnapshot = await _firestore
          .collection('subjects')
          .where('active', isEqualTo: true)
          .get();

      final subjects = subjectsSnapshot.docs
          .where((doc) => subjectIds.contains(doc.id))
          .map(
            (doc) => _StudentSubject(
              id: doc.id,
              nameAr: doc.data()['nameAr']?.toString() ?? '',
              nameEn: doc.data()['nameEn']?.toString() ?? '',
            ),
          )
          .toList();

      subjects.sort((a, b) => a.nameAr.compareTo(b.nameAr));

      if (!mounted) return;

      setState(() {
        _subjects = subjects;
        _selectedSubjectId =
            subjects.isNotEmpty ? subjects.first.id : null;
        _loadingSubjects = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _subjects = [];
        _selectedSubjectId = null;
        _loadingSubjects = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تحميل المواد: $e'),
        ),
      );
    }
  }

  Widget _buildSubjectSelector() {
    if (_loadingSubjects) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_subjects.isEmpty) {
      return const Card(
        margin: EdgeInsets.all(12),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'لا توجد مواد دراسية مرتبطة بهذا الطالب.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<String>(
          value: _selectedSubjectId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'اختر المادة',
            border: OutlineInputBorder(),
          ),
          items: _subjects.map((subject) {
            return DropdownMenuItem<String>(
              value: subject.id,
              child: Text(
                subject.nameAr.isNotEmpty
                    ? subject.nameAr
                    : subject.nameEn,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedSubjectId = value;
            });
          },
        ),
      ),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _lessonsStream(
    String subjectId,
  ) {
    return _firestore
        .collection('lessons')
        .where('subjectId', isEqualTo: subjectId)
        .where('active', isEqualTo: true)
        .snapshots();
  }

  Widget _buildLessonsList() {
    final subjectId = _selectedSubjectId;

    if (subjectId == null) {
      return const Expanded(
        child: Center(
          child: Text('اختر المادة أولًا'),
        ),
      );
    }

    return Expanded(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _lessonsStream(subjectId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'حدث خطأ أثناء تحميل الدروس:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final lessons = List<
              QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snapshot.data?.docs ?? [],
          );

          lessons.sort((a, b) {
            final orderA = (a.data()['order'] as num?)?.toInt() ?? 0;
            final orderB = (b.data()['order'] as num?)?.toInt() ?? 0;

            if (orderA != orderB) {
              return orderA.compareTo(orderB);
            }

            final createdA = a.data()['createdAt'] as Timestamp?;
            final createdB = b.data()['createdAt'] as Timestamp?;

            if (createdA == null && createdB == null) return 0;
            if (createdA == null) return 1;
            if (createdB == null) return -1;

            return createdA.compareTo(createdB);
          });

          if (lessons.isEmpty) {
            return RefreshIndicator(
              onRefresh: _loadStudentSubjects,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'لا توجد دروس متاحة في هذه المادة حتى الآن.',
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadStudentSubjects,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: lessons.length,
              itemBuilder: (context, index) {
                final lesson = lessons[index];
                final data = lesson.data();

                final title = data['title']?.toString() ?? 'بدون عنوان';
                final content = data['content']?.toString() ?? '';
                final order =
                    (data['order'] as num?)?.toInt() ?? index + 1;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showLessonDetails(
                      lessons,
                      index,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            child: Text('$order'),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (content.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    content,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_back_ios_new,
                            size: 17,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showLessonDetails(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> lessons,
    int index,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _StudentLessonDetailsScreen(
          lessons: lessons,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دروسي'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildSubjectSelector(),
              if (_subjects.isNotEmpty)
                _buildLessonsList()
              else
                const Expanded(
                  child: Center(
                    child: Text(
                      'لا توجد مواد دراسية مرتبطة بهذا الطالب.',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentLessonDetailsScreen extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> lessons;
  final int initialIndex;

  const _StudentLessonDetailsScreen({
    required this.lessons,
    required this.initialIndex,
  });

  @override
  State<_StudentLessonDetailsScreen> createState() =>
      _StudentLessonDetailsScreenState();
}

class _StudentLessonDetailsScreenState
    extends State<_StudentLessonDetailsScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _openLesson(int index) {
    if (index < 0 || index >= widget.lessons.length) return;

    setState(() {
      _currentIndex = index;
    });
  }

  String _lessonTitle(QueryDocumentSnapshot<Map<String, dynamic>> lesson) {
    return lesson.data()['title']?.toString() ?? 'بدون عنوان';
  }

  String _lessonContent(QueryDocumentSnapshot<Map<String, dynamic>> lesson) {
    return lesson.data()['content']?.toString() ?? '';
  }

  int _lessonOrder(
    QueryDocumentSnapshot<Map<String, dynamic>> lesson,
    int fallback,
  ) {
    return (lesson.data()['order'] as num?)?.toInt() ?? fallback + 1;
  }

  void _showLessonIndex() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Text(
                    'فهرس الدروس',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.lessons.length,
                    itemBuilder: (context, index) {
                      final lesson = widget.lessons[index];
                      final title = _lessonTitle(lesson);
                      final order = _lessonOrder(lesson, index);
                      final selected = index == _currentIndex;

                      return ListTile(
                        selected: selected,
                        leading: CircleAvatar(
                          child: Text('$order'),
                        ),
                        title: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? const Icon(Icons.menu_book)
                            : const Icon(Icons.chevron_left),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _openLesson(index);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lessons[_currentIndex];
    final title = _lessonTitle(lesson);
    final content = _lessonContent(lesson);
    final order = _lessonOrder(lesson, _currentIndex);
    final isFirst = _currentIndex == 0;
    final isLast = _currentIndex == widget.lessons.length - 1;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'الفهرس',
              onPressed: _showLessonIndex,
              icon: const Icon(Icons.list_alt),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      child: Text(
                        '$order',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'الدرس ${_currentIndex + 1} من ${widget.lessons.length}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: SelectableText(
                        content.isEmpty
                            ? 'لا يوجد محتوى لهذا الدرس.'
                            : content,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isFirst
                            ? null
                            : () => _openLesson(_currentIndex - 1),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('السابق'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: isLast
                            ? null
                            : () => _openLesson(_currentIndex + 1),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('التالي'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentSubject {
  final String id;
  final String nameAr;
  final String nameEn;

  const _StudentSubject({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });
}
