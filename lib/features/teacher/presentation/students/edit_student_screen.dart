import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditStudentScreen extends StatefulWidget {
  final String studentId;
  final Map<String, dynamic> studentData;

  const EditStudentScreen({
    super.key,
    required this.studentId,
    required this.studentData,
  });

  @override
  State<EditStudentScreen> createState() => _EditStudentScreenState();
}

class _EditStudentScreenState extends State<EditStudentScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _studentCodeController;

  String? _selectedClassId;
  late bool _active;

  bool _isSaving = false;
  bool _isLoadingSubjects = true;

  final Set<String> _selectedSubjectIds = {};

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _subjects = [];

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.studentData['name']?.toString() ?? '',
    );

    _studentCodeController = TextEditingController(
      text: widget.studentData['studentCode']?.toString() ?? '',
    );

    _selectedClassId =
        widget.studentData['classId']?.toString();

    _active = widget.studentData['active'] == true;

    _loadSubjects();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studentCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final firestore = FirebaseFirestore.instance;

      final subjectsFuture = firestore
          .collection('subjects')
          .where(
            'active',
            isEqualTo: true,
          )
          .get();

      final studentSubjectsFuture = firestore
          .collection('studentSubjects')
          .where(
            'studentId',
            isEqualTo: widget.studentId,
          )
          .get();

      final subjectsSnapshot = await subjectsFuture;
      final studentSubjectsSnapshot =
          await studentSubjectsFuture;

      final selectedIds = studentSubjectsSnapshot.docs
          .map(
            (doc) =>
                doc.data()['subjectId']?.toString(),
          )
          .whereType<String>()
          .toSet();

      if (!mounted) {
        return;
      }

      setState(() {
        _subjects = subjectsSnapshot.docs;

        _selectedSubjectIds
          ..clear()
          ..addAll(selectedIds);

        _isLoadingSubjects = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingSubjects = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر تحميل المواد: $error',
          ),
        ),
      );
    }
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار الفصل'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final name = _nameController.text.trim();
      final studentCode =
          _studentCodeController.text.trim();

      final firestore = FirebaseFirestore.instance;

      final existingStudent = await firestore
          .collection('students')
          .where(
            'studentCode',
            isEqualTo: studentCode,
          )
          .limit(2)
          .get();

      final duplicateExists = existingStudent.docs.any(
        (doc) => doc.id != widget.studentId,
      );

      if (duplicateExists) {
        throw Exception(
          'كود الطالب مستخدم بالفعل.',
        );
      }

      // تحميل العلاقات الحالية للطالب.
      final studentSubjectsSnapshot = await firestore
          .collection('studentSubjects')
          .where(
            'studentId',
            isEqualTo: widget.studentId,
          )
          .get();

      final batch = firestore.batch();

      final studentRef = firestore
          .collection('students')
          .doc(widget.studentId);

      final userId =
          widget.studentData['userId']?.toString() ??
              widget.studentId;

      final userRef = firestore
          .collection('users')
          .doc(userId);

      // تحديث بيانات الطالب.
      batch.update(studentRef, {
        'name': name,
        'studentCode': studentCode,
        'classId': _selectedClassId,
        'active': _active,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // تحديث بيانات المستخدم.
      batch.update(userRef, {
        'name': name,
        'active': _active,
      });

      // حذف المواد التي تم إلغاء اختيارها.
      for (final doc in studentSubjectsSnapshot.docs) {
        final subjectId =
            doc.data()['subjectId']?.toString();

        if (subjectId == null ||
            !_selectedSubjectIds.contains(subjectId)) {
          batch.delete(doc.reference);
        }
      }

      // إضافة المواد الجديدة.
      for (final subjectId in _selectedSubjectIds) {
        final exists = studentSubjectsSnapshot.docs.any(
          (doc) =>
              doc.data()['subjectId']?.toString() ==
              subjectId,
        );

        if (!exists) {
          final relationId =
              '${widget.studentId}_$subjectId';

          final relationRef = firestore
              .collection('studentSubjects')
              .doc(relationId);

          batch.set(relationRef, {
            'studentId': widget.studentId,
            'subjectId': subjectId,
            'createdAt':
                FieldValue.serverTimestamp(),
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
            'تم تحديث بيانات الطالب والمواد بنجاح',
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

  Widget _buildSubjectsSection() {
    if (_isLoadingSubjects) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_subjects.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'لا توجد مواد نشطة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'أضف مادة من إدارة المواد أولًا.',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: _subjects.map((doc) {
          final data = doc.data();

          final subjectId = doc.id;

          final nameAr =
              data['nameAr']?.toString() ?? '';

          final nameEn =
              data['nameEn']?.toString() ?? '';

          return CheckboxListTile(
            value: _selectedSubjectIds.contains(
              subjectId,
            ),
            title: Text(
              nameAr.isEmpty
                  ? 'مادة بدون اسم'
                  : nameAr,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: nameEn.isEmpty
                ? null
                : Text(nameEn),
            secondary: const Icon(
              Icons.menu_book_outlined,
            ),
            onChanged: _isSaving
                ? null
                : (value) {
                    setState(() {
                      if (value == true) {
                        _selectedSubjectIds.add(
                          subjectId,
                        );
                      } else {
                        _selectedSubjectIds.remove(
                          subjectId,
                        );
                      }
                    });
                  },
          );
        }).toList(),
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
            'تعديل الطالب',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'بيانات الطالب',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الطالب',
                      prefixIcon:
                          Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'يرجى إدخال اسم الطالب';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller:
                        _studentCodeController,
                    decoration: const InputDecoration(
                      labelText: 'كود الطالب',
                      prefixIcon:
                          Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'يرجى إدخال كود الطالب';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  StreamBuilder<
                      QuerySnapshot<
                          Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('classes')
                        .where(
                          'active',
                          isEqualTo: true,
                        )
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'الفصل',
                            prefixIcon:
                                Icon(Icons.groups_outlined),
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            'جاري تحميل الفصول...',
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return const InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'الفصل',
                            prefixIcon:
                                Icon(Icons.groups_outlined),
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            'حدث خطأ أثناء تحميل الفصول',
                          ),
                        );
                      }

                      final classes =
                          snapshot.data?.docs ?? [];

                      if (classes.isEmpty) {
                        return const InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'الفصل',
                            prefixIcon:
                                Icon(Icons.groups_outlined),
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            'لا توجد فصول متاحة',
                          ),
                        );
                      }

                      final selectedClassStillExists =
                          classes.any(
                        (doc) =>
                            doc.id == _selectedClassId,
                      );

                      return DropdownButtonFormField<String>(
                        value: selectedClassStillExists
                            ? _selectedClassId
                            : null,
                        decoration:
                            const InputDecoration(
                          labelText: 'الفصل',
                          prefixIcon:
                              Icon(Icons.groups_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: classes.map((doc) {
                          final data = doc.data();

                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(
                              data['name']
                                      ?.toString() ??
                                  '',
                            ),
                          );
                        }).toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedClassId =
                                      value;
                                });
                              },
                        validator: (value) {
                          if (value == null) {
                            return 'يرجى اختيار الفصل';
                          }

                          return null;
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  const Text(
                    'المواد التي يدرسها الطالب',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _buildSubjectsSection(),

                  const SizedBox(height: 20),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'حساب الطالب نشط',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _active
                          ? 'الطالب يستطيع تسجيل الدخول'
                          : 'الطالب لا يستطيع تسجيل الدخول',
                    ),
                    value: _active,
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            setState(() {
                              _active = value;
                            });
                          },
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : _saveStudent,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.save_outlined,
                            ),
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
