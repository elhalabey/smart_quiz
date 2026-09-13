import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditQuizScreen extends StatefulWidget {
  final String quizId;
  final Map<String, dynamic> quizData;

  const EditQuizScreen({
    super.key,
    required this.quizId,
    required this.quizData,
  });

  @override
  State<EditQuizScreen> createState() => _EditQuizScreenState();
}

class _EditQuizScreenState extends State<EditQuizScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  String? _selectedSubjectId;
  String? _selectedTeacherId;
  late String _selectedStatus;

  final Set<String> _selectedClassIds = {};

  DateTime? _startAt;
  DateTime? _endAt;

  bool _isSaving = false;
  bool _isLoadingClasses = true;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.quizData['title']?.toString() ?? '',
    );

    _descriptionController = TextEditingController(
      text: widget.quizData['description']?.toString() ?? '',
    );

    _selectedSubjectId = widget.quizData['subjectId']?.toString();
    _selectedTeacherId = widget.quizData['teacherId']?.toString();
    _selectedStatus =
        widget.quizData['status']?.toString() ?? 'draft';

    _startAt = _readDateTime(widget.quizData['startAt']);
    _endAt = _readDateTime(widget.quizData['endAt']);

    _loadClasses();
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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('quizClasses')
          .where('quizId', isEqualTo: widget.quizId)
          .get();

      final selectedIds = snapshot.docs
          .map(
            (doc) => doc.data()['classId']?.toString(),
          )
          .whereType<String>()
          .toSet();

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedClassIds
          ..clear()
          ..addAll(selectedIds);
        _isLoadingClasses = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingClasses = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحميل الفصول: $error'),
        ),
      );
    }
  }

  Future<DateTime?> _pickDateTime({
    required DateTime? initialDate,
  }) async {
    final now = DateTime.now();
    final initial = initialDate ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'اختر التاريخ',
      cancelText: 'إلغاء',
      confirmText: 'التالي',
    );

    if (date == null || !mounted) {
      return null;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'اختر الوقت',
      cancelText: 'إلغاء',
      confirmText: 'تم',
    );

    if (time == null) {
      return null;
    }

    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
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

  Future<void> _saveQuiz() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedSubjectId == null) {
      _showMessage('يرجى اختيار المادة');
      return;
    }

    if (_selectedTeacherId == null) {
      _showMessage('يرجى اختيار المعلم');
      return;
    }

    if (_selectedClassIds.isEmpty) {
      _showMessage('يرجى اختيار فصل واحد على الأقل');
      return;
    }

    if (_selectedStatus == 'published') {
      if (_startAt == null || _endAt == null) {
        _showMessage(
          'الاختبار المنشور يجب أن يحتوي على وقت بداية ونهاية',
        );
        return;
      }
    }

    if (_startAt != null &&
        _endAt != null &&
        !_endAt!.isAfter(_startAt!)) {
      _showMessage(
        'يجب أن يكون وقت النهاية بعد وقت البداية',
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      final existingClasses = await firestore
          .collection('quizClasses')
          .where('quizId', isEqualTo: widget.quizId)
          .get();

      final batch = firestore.batch();

      final quizRef = firestore
          .collection('quizzes')
          .doc(widget.quizId);

      batch.update(quizRef, {
        'title': _titleController.text.trim(),
        'subjectId': _selectedSubjectId,
        'teacherId': _selectedTeacherId,
        'description': _descriptionController.text.trim(),
        'status': _selectedStatus,
        'startAt': _startAt == null
            ? null
            : Timestamp.fromDate(_startAt!),
        'endAt': _endAt == null
            ? null
            : Timestamp.fromDate(_endAt!),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final doc in existingClasses.docs) {
        final classId = doc.data()['classId']?.toString();

        if (classId == null ||
            !_selectedClassIds.contains(classId)) {
          batch.delete(doc.reference);
        }
      }

      for (final classId in _selectedClassIds) {
        final exists = existingClasses.docs.any(
          (doc) => doc.data()['classId']?.toString() == classId,
        );

        if (!exists) {
          final relationRef = firestore
              .collection('quizClasses')
              .doc('${widget.quizId}_$classId');

          batch.set(relationRef, {
            'quizId': widget.quizId,
            'classId': classId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تحديث الاختبار والفصول بنجاح',
          ),
        ),
      );

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          ),
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
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildSubjectDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('subjects')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'المادة',
              prefixIcon: Icon(Icons.menu_book_outlined),
              border: OutlineInputBorder(),
            ),
            child: Text('جاري تحميل المواد...'),
          );
        }

        if (snapshot.hasError) {
          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'المادة',
              prefixIcon: Icon(Icons.menu_book_outlined),
              border: OutlineInputBorder(),
            ),
            child: Text('حدث خطأ أثناء تحميل المواد'),
          );
        }

        final subjects = snapshot.data?.docs ?? [];

        if (subjects.isEmpty) {
          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'المادة',
              prefixIcon: Icon(Icons.menu_book_outlined),
              border: OutlineInputBorder(),
            ),
            child: Text('لا توجد مواد نشطة'),
          );
        }

        final selectedExists =
            subjects.any((doc) => doc.id == _selectedSubjectId);

        return DropdownButtonFormField<String>(
          value: selectedExists ? _selectedSubjectId : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'المادة',
            prefixIcon: Icon(Icons.menu_book_outlined),
            border: OutlineInputBorder(),
          ),
          items: subjects.map((doc) {
            final data = doc.data();
            final nameAr = data['nameAr']?.toString() ?? '';
            final nameEn = data['nameEn']?.toString() ?? '';

            return DropdownMenuItem<String>(
              value: doc.id,
              child: Text(
                nameEn.isEmpty ? nameAr : '$nameAr - $nameEn',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            );
          }).toList(),
          onChanged: _isSaving
              ? null
              : (value) {
                  setState(() {
                    _selectedSubjectId = value;
                  });
                },
          validator: (value) {
            if (value == null) {
              return 'يرجى اختيار المادة';
            }
            return null;
          },
        );
      },
    );
  }

  Widget _buildTeacherDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'teacher')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'المعلم',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            child: Text('جاري تحميل المعلمين...'),
          );
        }

        if (snapshot.hasError) {
          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'المعلم',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            child: Text('حدث خطأ أثناء تحميل المعلمين'),
          );
        }

        final teachers = snapshot.data?.docs ?? [];

        if (teachers.isEmpty) {
          return const InputDecorator(
            decoration: InputDecoration(
              labelText: 'المعلم',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            child: Text('لا يوجد معلمون نشطون'),
          );
        }

        final selectedExists =
            teachers.any((doc) => doc.id == _selectedTeacherId);

        return DropdownButtonFormField<String>(
          value: selectedExists ? _selectedTeacherId : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'المعلم',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          items: teachers.map((doc) {
            final data = doc.data();

            return DropdownMenuItem<String>(
              value: doc.id,
              child: Text(
                data['name']?.toString() ?? 'معلم بدون اسم',
              ),
            );
          }).toList(),
          onChanged: _isSaving
              ? null
              : (value) {
                  setState(() {
                    _selectedTeacherId = value;
                  });
                },
          validator: (value) {
            if (value == null) {
              return 'يرجى اختيار المعلم';
            }
            return null;
          },
        );
      },
    );
  }

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedStatus,
      decoration: const InputDecoration(
        labelText: 'حالة الاختبار',
        prefixIcon: Icon(Icons.flag_outlined),
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
    );
  }

  Widget _buildDateTimeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required DateTime? value,
    required VoidCallback onPressed,
    required VoidCallback onClear,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: value == null
            ? IconButton(
                tooltip: 'تحديد',
                onPressed: _isSaving ? null : onPressed,
                icon: const Icon(Icons.calendar_month_outlined),
              )
            : Wrap(
                spacing: 2,
                children: [
                  IconButton(
                    tooltip: 'تعديل',
                    onPressed: _isSaving ? null : onPressed,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'مسح',
                    onPressed: _isSaving ? null : onClear,
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'موعد الاختبار',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildDateTimeCard(
          title: 'وقت البداية',
          subtitle: _formatDateTime(_startAt),
          icon: Icons.play_circle_outline,
          value: _startAt,
          onPressed: () async {
            final value = await _pickDateTime(
              initialDate: _startAt,
            );
            if (value != null && mounted) {
              setState(() {
                _startAt = value;
              });
            }
          },
          onClear: () {
            setState(() {
              _startAt = null;
            });
          },
        ),
        _buildDateTimeCard(
          title: 'وقت النهاية',
          subtitle: _formatDateTime(_endAt),
          icon: Icons.stop_circle_outlined,
          value: _endAt,
          onPressed: () async {
            final value = await _pickDateTime(
              initialDate: _endAt ?? _startAt,
            );
            if (value != null && mounted) {
              setState(() {
                _endAt = value;
              });
            }
          },
          onClear: () {
            setState(() {
              _endAt = null;
            });
          },
        ),
        const SizedBox(height: 4),
        const Text(
          'عند نشر الاختبار يجب أن يكون له وقت بداية ونهاية، ويجب أن تكون النهاية بعد البداية.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildClassesSection() {
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

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('classes')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'حدث خطأ أثناء تحميل الفصول',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final classes = snapshot.data?.docs ?? [];

        if (classes.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'لا توجد فصول نشطة',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Card(
          child: Column(
            children: classes.map((doc) {
              final data = doc.data();

              return CheckboxListTile(
                value: _selectedClassIds.contains(doc.id),
                secondary: const Icon(Icons.groups_outlined),
                title: Text(
                  data['name']?.toString() ?? 'فصل بدون اسم',
                ),
                subtitle: data['grade'] != null
                    ? Text('الصف: ${data['grade']}')
                    : null,
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          if (value == true) {
                            _selectedClassIds.add(doc.id);
                          } else {
                            _selectedClassIds.remove(doc.id);
                          }
                        });
                      },
              );
            }).toList(),
          ),
        );
      },
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
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'بيانات الاختبار',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'عنوان الاختبار',
                      prefixIcon: Icon(Icons.assignment_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'يرجى إدخال عنوان الاختبار';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'وصف الاختبار',
                      prefixIcon: Icon(Icons.description_outlined),
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSubjectDropdown(),
                  const SizedBox(height: 16),
                  _buildTeacherDropdown(),
                  const SizedBox(height: 16),
                  _buildStatusDropdown(),
                  const SizedBox(height: 28),
                  _buildScheduleSection(),
                  const SizedBox(height: 28),
                  const Text(
                    'الفصول المستهدفة',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildClassesSection(),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveQuiz,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _isSaving
                            ? 'جاري الحفظ...'
                            : 'حفظ التعديلات',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
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
