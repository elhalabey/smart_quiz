import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';

class EditTeacherQuizScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final String quizId;
  final Map<String, dynamic> quizData;

  const EditTeacherQuizScreen({
    super.key,
    required this.sessionManager,
    required this.quizId,
    required this.quizData,
  });

  @override
  State<EditTeacherQuizScreen> createState() =>
      _EditTeacherQuizScreenState();
}

class _EditTeacherQuizScreenState
    extends State<EditTeacherQuizScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedSubjectId;

  final Set<String> _selectedClassIds = {};

  final Map<String, Set<String>> _assignmentPairs = {};

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _subjects = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];

  DateTime? _startAt;
  DateTime? _endAt;

  // Quiz status
  String _selectedStatus = 'draft';

  bool _isLoading = true;
  bool _isLoadingClasses = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _titleController.text =
        widget.quizData['title']?.toString() ?? '';

    _descriptionController.text =
        widget.quizData['description']?.toString() ?? '';

    _selectedSubjectId =
        widget.quizData['subjectId']?.toString();

    _selectedStatus = switch (widget.quizData['status']?.toString()) {
  'draft' => 'draft',
  'published' => 'published',
  'closed' => 'closed',
  'archived' => 'archived',
  _ => 'draft',
};


    final startAt = widget.quizData['startAt'];

    if (startAt is Timestamp) {
      _startAt = startAt.toDate();
    }

    final endAt = widget.quizData['endAt'];

    if (endAt is Timestamp) {
      _endAt = endAt.toDate();
    }

    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final firestore = FirebaseFirestore.instance;

      final teacherId =
          widget.sessionManager.currentSession!.uid;

      /*
       * تحميل:
       * 1. المواد التي يدرسها المعلم.
       * 2. التكليفات التي تربط المعلم بالمادة والفصل.
       * 3. الفصول المرتبطة بالاختبار الحالي.
       */

      final teacherSubjectsSnapshot = await firestore
          .collection('teacherSubjects')
          .where(
            'teacherId',
            isEqualTo: teacherId,
          )
          .get();

      final teacherAssignmentsSnapshot = await firestore
          .collection('teacherAssignments')
          .where(
            'teacherId',
            isEqualTo: teacherId,
          )
          .get();

      final quizClassesSnapshot = await firestore
          .collection('quizClasses')
          .where(
            'quizId',
            isEqualTo: widget.quizId,
          )
          .get();

      final subjectIds = <String>{};

      for (final doc in teacherSubjectsSnapshot.docs) {
        final subjectId =
            doc.data()['subjectId']?.toString();

        if (subjectId != null &&
            subjectId.isNotEmpty) {
          subjectIds.add(subjectId);
        }
      }

      final assignmentPairs = <String, Set<String>>{};

      for (final doc in teacherAssignmentsSnapshot.docs) {
        final data = doc.data();

        final subjectId =
            data['subjectId']?.toString();

        final classId =
            data['classId']?.toString();

        if (subjectId == null ||
            subjectId.isEmpty ||
            classId == null ||
            classId.isEmpty) {
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

      final selectedClassIds = <String>{};

      for (final doc in quizClassesSnapshot.docs) {
        final classId =
            doc.data()['classId']?.toString();

        if (classId != null &&
            classId.isNotEmpty) {
          selectedClassIds.add(classId);
        }
      }

      final subjectsSnapshot = await firestore
          .collection('subjects')
          .where(
            'active',
            isEqualTo: true,
          )
          .get();

      final subjects = subjectsSnapshot.docs
          .where(
            (doc) => subjectIds.contains(doc.id),
          )
          .toList();

      subjects.sort((a, b) {
        final aName =
            a.data()['nameAr']?.toString() ?? '';

        final bName =
            b.data()['nameAr']?.toString() ?? '';

        return aName.compareTo(bName);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _subjects = subjects;

        _assignmentPairs
          ..clear()
          ..addAll(assignmentPairs);

        _selectedClassIds
          ..clear()
          ..addAll(selectedClassIds);

        _isLoading = false;
      });

      /*
       * بعد تحميل التكليفات والفصول الحالية:
       * نعرض فقط الفصول المسموح بها للمادة الحالية.
       */
      if (_selectedSubjectId != null &&
          subjectIds.contains(_selectedSubjectId)) {
        await _loadClassesForSelectedSubject(
          _selectedSubjectId!,
          preserveExistingSelection: true,
        );
      } else if (mounted) {
        setState(() {
          _selectedSubjectId = null;
          _selectedClassIds.clear();
          _classes = [];
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        'حدث خطأ أثناء تحميل بيانات الاختبار:\n$error',
      );
    }
  }

  Future<void> _loadClassesForSelectedSubject(
    String subjectId, {
    bool preserveExistingSelection = false,
  }) async {
    setState(() {
      _isLoadingClasses = true;

      if (!preserveExistingSelection) {
        _selectedClassIds.clear();
      }
    });

    try {
      final firestore = FirebaseFirestore.instance;

      final allowedClassIds =
          _assignmentPairs[subjectId] ??
              <String>{};

      if (allowedClassIds.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _classes = [];
          _selectedClassIds.clear();
          _isLoadingClasses = false;
        });

        return;
      }

      final classesSnapshot = await firestore
          .collection('classes')
          .where(
            'active',
            isEqualTo: true,
          )
          .get();

      final classes = classesSnapshot.docs
          .where(
            (doc) => allowedClassIds.contains(doc.id),
          )
          .toList();

      classes.sort((a, b) {
        final aName =
            a.data()['name']?.toString() ?? '';

        final bName =
            b.data()['name']?.toString() ?? '';

        return aName.compareTo(bName);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = classes;

        /*
         * أثناء فتح الاختبار لأول مرة:
         * نحتفظ فقط بالفصول القديمة الموجودة
         * ضمن تكليف المعلم لهذه المادة.
         *
         * لو كان هناك فصل قديم لم يعد المعلم مكلفًا به،
         * يتم إزالته من الاختيارات.
         */
        _selectedClassIds.removeWhere(
          (classId) => !allowedClassIds.contains(classId),
        );

        _isLoadingClasses = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _classes = [];
        _isLoadingClasses = false;
      });

      _showMessage(
        'حدث خطأ أثناء تحميل الفصول:\n$error',
      );
    }
  }

  Future<bool> _validateAssignments() async {
    final teacherId =
        widget.sessionManager.currentSession!.uid;

    final subjectId = _selectedSubjectId;

    if (subjectId == null) {
      return false;
    }

    final snapshot = await FirebaseFirestore.instance
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
      final classId =
          doc.data()['classId']?.toString();

      if (classId != null &&
          classId.isNotEmpty) {
        allowedClassIds.add(classId);
      }
    }

    return _selectedClassIds.every(
      allowedClassIds.contains,
    );
  }

  Future<void> _selectStartDateTime() async {
    final now = DateTime.now();

    final initialDate =
        _startAt ?? now;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(
        now.year - 1,
      ),
      lastDate: DateTime(
        now.year + 5,
      ),
    );

    if (selectedDate == null ||
        !mounted) {
      return;
    }

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _startAt ?? now,
      ),
    );

    if (selectedTime == null ||
        !mounted) {
      return;
    }

    setState(() {
      _startAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  Future<void> _selectEndDateTime() async {
    final now = DateTime.now();

    final initialDate =
        _endAt ?? _startAt ?? now;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(
        now.year - 1,
      ),
      lastDate: DateTime(
        now.year + 5,
      ),
    );

    if (selectedDate == null ||
        !mounted) {
      return;
    }

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _endAt ?? _startAt ?? now,
      ),
    );

    if (selectedTime == null ||
        !mounted) {
      return;
    }

    setState(() {
      _endAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'غير محدد';
    }

    final day =
        value.day.toString().padLeft(2, '0');

    final month =
        value.month.toString().padLeft(2, '0');

    final year =
        value.year.toString();

    final hour =
        value.hour.toString().padLeft(2, '0');

    final minute =
        value.minute.toString().padLeft(2, '0');

    return '$day/$month/$year - $hour:$minute';
  }

  Future<void> _saveQuiz() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedSubjectId == null) {
      _showMessage('يرجى اختيار المادة');
      return;
    }

    if (_selectedClassIds.isEmpty) {
      _showMessage(
        'يرجى اختيار فصل واحد على الأقل',
      );
      return;
    }

    if (_startAt != null &&
        _endAt != null &&
        !_endAt!.isAfter(_startAt!)) {
      _showMessage(
        'وقت نهاية الاختبار يجب أن يكون بعد وقت البداية',
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final firestore =
          FirebaseFirestore.instance;

      final validAssignments =
          await _validateAssignments();

      if (!validAssignments) {
        throw Exception(
          'يوجد فصل غير مسموح لك به في هذه المادة.',
        );
      }

      final existingClasses =
          await firestore
              .collection('quizClasses')
              .where(
                'quizId',
                isEqualTo: widget.quizId,
              )
              .get();

      final quizRef = firestore
          .collection('quizzes')
          .doc(widget.quizId);

      final batch = firestore.batch();

      /*
       * تحديث الاختبار.
       *
       * teacherId يظل هو المعلم الحالي،
       * ولا يستطيع المعلم تغيير مالك الاختبار.
       */
      batch.update(
        quizRef,
        {
          'title':
              _titleController.text.trim(),
          'subjectId':
              _selectedSubjectId,
          'description':
              _descriptionController.text.trim(),
          'status': _selectedStatus,
          'startAt': _startAt == null
              ? null
              : Timestamp.fromDate(
                  _startAt!,
                ),
          'endAt': _endAt == null
              ? null
              : Timestamp.fromDate(
                  _endAt!,
                ),
          'updatedAt':
              FieldValue.serverTimestamp(),
        },
      );

      final existingClassIds = <String>{};

      /*
       * حذف الفصول التي لم تعد مختارة.
       */
      for (final doc in existingClasses.docs) {
        final classId =
            doc.data()['classId']?.toString();

        if (classId == null) {
          batch.delete(doc.reference);
          continue;
        }

        existingClassIds.add(classId);

        if (!_selectedClassIds.contains(
          classId,
        )) {
          batch.delete(doc.reference);
        }
      }

      /*
       * إضافة الفصول الجديدة.
       */
      for (final classId in _selectedClassIds) {
        if (existingClassIds.contains(
          classId,
        )) {
          continue;
        }

        final relationRef = firestore
            .collection('quizClasses')
            .doc(
              '${widget.quizId}_$classId',
            );

        batch.set(
          relationRef,
          {
            'quizId':
                widget.quizId,
            'classId':
                classId,
            'createdAt':
                FieldValue.serverTimestamp(),
          },
        );
      }

      await batch.commit();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تعديل الاختبار والفصول بنجاح',
          ),
        ),
      );

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.toString().replaceFirst(
          'Exception: ',
          '',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Widget _buildSubjectDropdown() {
    if (_subjects.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'المادة',
          prefixIcon:
              Icon(Icons.menu_book_outlined),
          border: OutlineInputBorder(),
        ),
        child: Text(
          'لا توجد مواد مكلف بها',
        ),
      );
    }

    final selectedExists = _subjects.any(
      (doc) => doc.id == _selectedSubjectId,
    );

    return DropdownButtonFormField<String>(
     isExpanded: true,
      value: selectedExists
          ? _selectedSubjectId
          : null,
      decoration: const InputDecoration(
        labelText: 'المادة',
        prefixIcon:
            Icon(Icons.menu_book_outlined),
        border: OutlineInputBorder(),
      ),
      items: _subjects.map((doc) {
        final data = doc.data();

        final nameAr =
            data['nameAr']?.toString() ?? '';

        final nameEn =
            data['nameEn']?.toString() ?? '';

        return DropdownMenuItem<String>(
          value: doc.id,
          child: Text(
            nameEn.isEmpty
                ? nameAr
                : '$nameAr - $nameEn',
                maxLines: 1,
    overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: _isSaving
          ? null
          : (value) async {
              if (value == null) {
                return;
              }

              setState(() {
                _selectedSubjectId = value;
                _selectedClassIds.clear();
                _classes = [];
              });

              await _loadClassesForSelectedSubject(
                value,
              );
            },
      validator: (value) {
        if (value == null) {
          return 'يرجى اختيار المادة';
        }

        return null;
      },
    );
  }

  Widget _buildClassesSection() {
    if (_selectedSubjectId == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'اختر المادة أولًا لعرض الفصول المسموح بها',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    if (_isLoadingClasses) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_classes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'لا يوجد فصول مكلف بها في هذه المادة',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: _classes.map((doc) {
          final data = doc.data();

          final className =
              data['name']?.toString() ??
                  'فصل بدون اسم';

          final grade =
              data['grade']?.toString() ??
                  '';

          return CheckboxListTile(
            value:
                _selectedClassIds.contains(
              doc.id,
            ),
            secondary: const Icon(
              Icons.groups_outlined,
            ),
            title: Text(
              className,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: grade.isEmpty
                ? null
                : Text(
                    'الصف: $grade',
                  ),
            onChanged: _isSaving
                ? null
                : (value) {
                    setState(() {
                      if (value == true) {
                        _selectedClassIds.add(
                          doc.id,
                        );
                      } else {
                        _selectedClassIds.remove(
                          doc.id,
                        );
                      }
                    });
                  },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateTimeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(
                Icons.play_circle_outline,
              ),
              title: const Text(
                'بداية الاختبار',
              ),
              subtitle: Text(
                _formatDateTime(_startAt),
              ),
              trailing: TextButton(
                onPressed: _isSaving
                    ? null
                    : _selectStartDateTime,
                child: const Text(
                  'اختيار',
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.stop_circle_outlined,
              ),
              title: const Text(
                'نهاية الاختبار',
              ),
              subtitle: Text(
                _formatDateTime(_endAt),
              ),
              trailing: TextButton(
                onPressed: _isSaving
                    ? null
                    : _selectEndDateTime,
                child: const Text(
                  'اختيار',
                ),
              ),
            ),
          ],
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
          title: const Text(
            'تعديل الاختبار',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: _isLoading
            ? const Center(
                child:
                    CircularProgressIndicator(),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .stretch,
                      children: [
                        const Text(
                          'بيانات الاختبار',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(
                          height: 20,
                        ),

                        TextFormField(
                          controller:
                              _titleController,
                          textInputAction:
                              TextInputAction.next,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'عنوان الاختبار',
                            prefixIcon: Icon(
                              Icons
                                  .assignment_outlined,
                            ),
                            border:
                                OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty) {
                              return 'يرجى إدخال عنوان الاختبار';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        TextFormField(
                          controller:
                              _descriptionController,
                          maxLines: 3,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'وصف الاختبار',
                            prefixIcon: Icon(
                              Icons
                                  .description_outlined,
                            ),
                            border:
                                OutlineInputBorder(),
                            alignLabelWithHint:
                                true,
                          ),
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        _buildSubjectDropdown(),

                        const SizedBox(
                          height: 16,
                        ),

                        DropdownButtonFormField<String>(
                          value: _selectedStatus,
                          decoration: const InputDecoration(
                            labelText: 'حالة الاختبار',
                            prefixIcon: Icon(
                              Icons.flag_outlined,
                            ),
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
                          onChanged: _isSaving
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

                        const SizedBox(
                          height: 24,
                        ),

                        const Text(
                          'الفصول المستهدفة',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Text(
                          'تظهر هنا فقط الفصول التي تم تكليفك بها في المادة المختارة.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            )
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        _buildClassesSection(),

                        const SizedBox(
                          height: 24,
                        ),

                        const Text(
                          'موعد الاختبار',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        _buildDateTimeSection(),

                        const SizedBox(
                          height: 28,
                        ),

                        SizedBox(
                          height: 52,
                          child:
                              ElevatedButton.icon(
                            onPressed:
                                _isSaving
                                    ? null
                                    : _saveQuiz,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth:
                                          2,
                                    ),
                                  )
                                : const Icon(
                                    Icons
                                        .save_outlined,
                                  ),
                            label: Text(
                              _isSaving
                                  ? 'جاري الحفظ...'
                                  : 'حفظ التعديلات',
                              style:
                                  const TextStyle(
                                fontSize: 17,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
