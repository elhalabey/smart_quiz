import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';
import '../questions/teacher_quiz_questions_screen.dart';

class AddTeacherQuizScreen extends StatefulWidget {
  final SessionManager sessionManager;

  const AddTeacherQuizScreen({
    super.key,
    required this.sessionManager,
  });

  @override
  State<AddTeacherQuizScreen> createState() =>
      _AddTeacherQuizScreenState();
}

class _AddTeacherQuizScreenState
    extends State<AddTeacherQuizScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedSubjectId;

  final Set<String> _selectedClassIds = {};

  DateTime? _startAt;
  DateTime? _endAt;

  // Quiz status
  String _selectedStatus = 'draft';

  bool _loading = true;
  bool _saving = false;
  bool _loadingClasses = false;

  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classes = [];

  final Map<String, Set<String>> _assignmentPairs = {};

  @override
  void initState() {
    super.initState();
    _loadTeacherAssignments();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTeacherAssignments() async {
    final teacherId =
        widget.sessionManager.currentSession?.uid;

    if (teacherId == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;

      final assignmentRelations = await firestore
          .collection('teacherAssignments')
          .where(
            'teacherId',
            isEqualTo: teacherId,
          )
          .get();

      final subjectIds = <String>{};

      final assignmentPairs =
          <String, Set<String>>{};

      for (final doc in assignmentRelations.docs) {
        final data = doc.data();

        final subjectId =
            data['subjectId'] as String?;

        final classId =
            data['classId'] as String?;

        if (subjectId == null || classId == null) {
          continue;
        }

        subjectIds.add(subjectId);

        assignmentPairs
            .putIfAbsent(
              subjectId,
              () => <String>{},
            )
            .add(classId);
      }

      final subjectSnapshot =
          await firestore.collection('subjects').get();

      final subjects = <Map<String, dynamic>>[];

      for (final doc in subjectSnapshot.docs) {
        if (!subjectIds.contains(doc.id)) {
          continue;
        }

        final data = doc.data();

        if (data['active'] == false) {
          continue;
        }

        subjects.add({
          'id': doc.id,
          ...data,
        });
      }

      subjects.sort(
        (a, b) =>
            (a['nameAr'] as String? ?? '')
                .compareTo(
          b['nameAr'] as String? ?? '',
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _subjects = subjects;

        _assignmentPairs
          ..clear()
          ..addAll(assignmentPairs);

        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ أثناء تحميل بيانات المعلم: $e',
          ),
        ),
      );
    }
  }

  Future<void> _loadClassesForSelectedSubject(
    String subjectId,
  ) async {
    final allowedClassIds =
        _assignmentPairs[subjectId] ?? <String>{};

    if (!mounted) {
      return;
    }

    setState(() {
      _loadingClasses = true;
      _classes = [];
      _selectedClassIds.clear();
    });

    if (allowedClassIds.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingClasses = false;
      });

      return;
    }

    try {
      final classSnapshot = await FirebaseFirestore
          .instance
          .collection('classes')
          .where(
            'active',
            isEqualTo: true,
          )
          .get();

      final classes = <Map<String, dynamic>>[];

      for (final doc in classSnapshot.docs) {
        if (!allowedClassIds.contains(doc.id)) {
          continue;
        }

        final data = doc.data();

        classes.add({
          'id': doc.id,
          ...data,
        });
      }

      classes.sort(
        (a, b) =>
            (a['name'] as String? ?? '')
                .compareTo(
          b['name'] as String? ?? '',
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = classes;
        _loadingClasses = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingClasses = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ أثناء تحميل الفصول: $e',
          ),
        ),
      );
    }
  }

  Future<bool> _validateAssignments(
    String teacherId,
    String subjectId,
    Set<String> classIds,
  ) async {
    if (classIds.isEmpty) {
      return false;
    }

    final snapshot = await FirebaseFirestore
        .instance
        .collection('teacherAssignments')
        .where(
          'teacherId',
          isEqualTo: teacherId,
        )
        .where(
          'subjectId',
          isEqualTo: subjectId,
        )
        .get();

    final allowedClassIds = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final classId =
          data['classId'] as String?;

      if (classId != null) {
        allowedClassIds.add(classId);
      }
    }

    return classIds.every(
      allowedClassIds.contains,
    );
  }

  Future<void> _selectStartDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _startAt ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: _startAt != null
          ? TimeOfDay.fromDateTime(_startAt!)
          : TimeOfDay.now(),
    );

    if (time == null || !mounted) {
      return;
    }

    setState(() {
      _startAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      if (_endAt != null &&
          !_endAt!.isAfter(_startAt!)) {
        _endAt = null;
      }
    });
  }

  Future<void> _selectEndDateTime() async {
    final initialDate =
        _endAt ??
        _startAt ??
        DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate:
          _startAt ?? DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: _endAt != null
          ? TimeOfDay.fromDateTime(_endAt!)
          : TimeOfDay.now(),
    );

    if (time == null || !mounted) {
      return;
    }

    final selectedEnd = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (_startAt != null &&
        !selectedEnd.isAfter(_startAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يجب أن يكون وقت النهاية بعد وقت البداية',
          ),
        ),
      );

      return;
    }

    setState(() {
      _endAt = selectedEnd;
    });
  }

  String _formatDateTime(
    DateTime? dateTime,
  ) {
    if (dateTime == null) {
      return 'غير محدد';
    }

    final day =
        dateTime.day.toString().padLeft(2, '0');

    final month =
        dateTime.month.toString().padLeft(2, '0');

    final year =
        dateTime.year.toString();

    final hour =
        dateTime.hour.toString().padLeft(2, '0');

    final minute =
        dateTime.minute.toString().padLeft(2, '0');

    return '$day/$month/$year - $hour:$minute';
  }

  Future<void> _saveQuiz() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedSubjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'اختر المادة أولًا',
          ),
        ),
      );

      return;
    }

    if (_selectedClassIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'اختر فصلًا واحدًا على الأقل',
          ),
        ),
      );

      return;
    }

    if (_startAt != null &&
        _endAt != null &&
        !_endAt!.isAfter(_startAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يجب أن يكون وقت النهاية بعد وقت البداية',
          ),
        ),
      );

      return;
    }

    final teacherId =
        widget.sessionManager.currentSession?.uid;

    if (teacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لم يتم العثور على بيانات المعلم',
          ),
        ),
      );

      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final subjectId = _selectedSubjectId!;

      // ============================================================
      // تشخيص 1: التحقق من teacherAssignments
      // ============================================================
      bool hasAssignments;

      try {
        debugPrint(
          'SAVE QUIZ - START _validateAssignments',
        );

        debugPrint(
          'SAVE QUIZ - teacherId: $teacherId',
        );

        debugPrint(
          'SAVE QUIZ - subjectId: $subjectId',
        );

        debugPrint(
          'SAVE QUIZ - classIds: $_selectedClassIds',
        );

        hasAssignments =
            await _validateAssignments(
          teacherId,
          subjectId,
          _selectedClassIds,
        );

        debugPrint(
          'SAVE QUIZ - _validateAssignments RESULT: $hasAssignments',
        );
      } catch (e) {
        debugPrint(
          'SAVE QUIZ - ERROR IN _validateAssignments: $e',
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _saving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في التحقق من تكليف المعلم:\n$e',
            ),
            duration: const Duration(
              seconds: 8,
            ),
          ),
        );

        return;
      }

      if (!mounted) {
        return;
      }

      if (!hasAssignments) {
        setState(() {
          _saving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لا يمكنك إنشاء اختبار لهذه المادة أو الفصول المحددة',
            ),
          ),
        );

        return;
      }

      final firestore =
          FirebaseFirestore.instance;

      final quizRef =
          firestore.collection('quizzes').doc();

      final batch = firestore.batch();

      debugPrint(
        'SAVE QUIZ - NEW QUIZ ID: ${quizRef.id}',
      );

      debugPrint(
        'SAVE QUIZ - START batch.set quizzes',
      );

      batch.set(
        quizRef,
        {
          'title':
              _titleController.text.trim(),
          'subjectId': subjectId,
          'teacherId': teacherId,
          'description':
              _descriptionController.text.trim(),
          'status': _selectedStatus,
          'createdAt':
              FieldValue.serverTimestamp(),
          'startAt': _startAt == null
              ? null
              : Timestamp.fromDate(_startAt!),
          'endAt': _endAt == null
              ? null
              : Timestamp.fromDate(_endAt!),
          'updatedAt':
              FieldValue.serverTimestamp(),
        },
      );

      debugPrint(
        'SAVE QUIZ - quizzes batch.set DONE',
      );

      for (final classId in _selectedClassIds) {
        final relationRef = firestore
            .collection('quizClasses')
            .doc(
              '${quizRef.id}_$classId',
            );

        debugPrint(
          'SAVE QUIZ - ADD quizClasses: ${relationRef.id}',
        );

        batch.set(
          relationRef,
          {
            'quizId': quizRef.id,
            'classId': classId,
            'teacherId': teacherId,
            'subjectId': subjectId,
            'createdAt':
                FieldValue.serverTimestamp(),
          },
        );
      }

      debugPrint(
        'SAVE QUIZ - ALL batch.set OPERATIONS DONE',
      );

      // ============================================================
      // تشخيص 2: تنفيذ batch.commit
      // ============================================================
      try {
        debugPrint(
          'SAVE QUIZ - START batch.commit',
        );

        await batch.commit();

        debugPrint(
          'SAVE QUIZ - batch.commit SUCCESS',
        );
      } catch (e) {
        debugPrint(
          'SAVE QUIZ - ERROR IN batch.commit: $e',
        );

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ أثناء حفظ الاختبار في Firestore:\n$e',
            ),
            duration: const Duration(
              seconds: 10,
            ),
          ),
        );

        return;
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إنشاء الاختبار بنجاح',
          ),
        ),
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TeacherQuizQuestionsScreen(
            sessionManager: widget.sessionManager,
            quizId: quizRef.id,
            quizTitle: _titleController.text.trim(),
            subjectId: subjectId,
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } catch (e) {
      debugPrint(
        'SAVE QUIZ - UNEXPECTED ERROR: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطأ غير متوقع أثناء إنشاء الاختبار:\n$e',
          ),
          duration: const Duration(
            seconds: 10,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إضافة اختبار',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding:
                      const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller:
                          _titleController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'عنوان الاختبار',
                        border:
                            OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null ||
                            value.trim().isEmpty) {
                          return 'أدخل عنوان الاختبار';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller:
                          _descriptionController,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(
                        labelText: 'الوصف',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value:
                          _selectedSubjectId,
                      decoration:
                          const InputDecoration(
                        labelText: 'المادة',
                        border:
                            OutlineInputBorder(),
                      ),
                      items:
                          _subjects.map((subject) {
                        final id =
                            subject['id']
                                as String;

                        final name =
                            subject['nameAr']
                                as String? ??
                            subject['nameEn']
                                as String? ??
                            'بدون اسم';

                        return DropdownMenuItem<
                            String>(
                          value: id,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _selectedSubjectId =
                              value;
                          _selectedClassIds.clear();
                          _classes = [];
                        });

                        await _loadClassesForSelectedSubject(
                          value,
                        );
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'اختر المادة';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'الفصول',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_selectedSubjectId ==
                        null)
                      const Card(
                        child: Padding(
                          padding:
                              EdgeInsets.all(16),
                          child: Text(
                            'اختر المادة أولًا لعرض الفصول المسموح بها',
                          ),
                        ),
                      )
                    else if (_loadingClasses)
                      const Card(
                        child: Padding(
                          padding:
                              EdgeInsets.all(16),
                          child: Center(
                            child:
                                CircularProgressIndicator(),
                          ),
                        ),
                      )
                    else if (_classes.isEmpty)
                      const Card(
                        child: Padding(
                          padding:
                              EdgeInsets.all(16),
                          child: Text(
                            'لا يوجد فصول مكلف بها في هذه المادة',
                          ),
                        ),
                      )
                    else
                      ..._classes.map(
                        (classData) {
                          final classId =
                              classData['id']
                                  as String;

                          final className =
                              classData['name']
                                  as String? ??
                              'بدون اسم';

                          return CheckboxListTile(
                            value:
                                _selectedClassIds
                                    .contains(
                              classId,
                            ),
                            title:
                                Text(className),
                            onChanged: (value) {
                              setState(() {
                                if (value ==
                                    true) {
                                  _selectedClassIds
                                      .add(
                                    classId,
                                  );
                                } else {
                                  _selectedClassIds
                                      .remove(
                                    classId,
                                  );
                                }
                              });
                            },
                          );
                        },
                      ),
                    const SizedBox(height: 20),
                    const Text(
                      'موعد الاختبار',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons
                              .play_arrow_outlined,
                        ),
                        title: const Text(
                          'بداية الاختبار',
                        ),
                        subtitle: Text(
                          _formatDateTime(
                            _startAt,
                          ),
                        ),
                        trailing: const Icon(
                          Icons
                              .calendar_month_outlined,
                        ),
                        onTap:
                            _selectStartDateTime,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.stop_outlined,
                        ),
                        title: const Text(
                          'نهاية الاختبار',
                        ),
                        subtitle: Text(
                          _formatDateTime(
                            _endAt,
                          ),
                        ),
                        trailing: const Icon(
                          Icons
                              .calendar_month_outlined,
                        ),
                        onTap:
                            _selectEndDateTime,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'حالة الاختبار',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'draft',
                          child: Text('مسودة'),
                        ),
                        DropdownMenuItem(
                          value: 'published',
                          child: Text('منشور'),
                        ),
                        DropdownMenuItem(
                          value: 'closed',
                          child: Text('مغلق'),
                        ),
                        DropdownMenuItem(
                          value: 'archived',
                          child: Text('مؤرشف'),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedStatus = value;
                              });
                            },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child:
                          FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : _saveQuiz,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons
                                    .save_outlined,
                              ),
                        label: Text(
                          _saving
                              ? 'جاري الحفظ...'
                              : 'حفظ الاختبار',
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
