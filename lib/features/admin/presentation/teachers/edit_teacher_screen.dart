import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditTeacherScreen extends StatefulWidget {
  final String teacherId;
  final Map<String, dynamic> teacherData;
  final Map<String, dynamic> userData;

  const EditTeacherScreen({
    super.key,
    required this.teacherId,
    required this.teacherData,
    required this.userData,
  });

  @override
  State<EditTeacherScreen> createState() => _EditTeacherScreenState();
}

class _EditTeacherScreenState extends State<EditTeacherScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;

  late bool _active;

  bool _isSaving = false;
  bool _isLoadingSubjects = true;
  bool _isLoadingAssignments = true;

  final Set<String> _selectedSubjectIds = {};
  final Set<String> _selectedAssignmentIds = {};

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _subjects = [];

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.userData['name']?.toString() ?? '',
    );

    _active = widget.teacherData['active'] == true;

    _loadSubjects();
    _loadAssignments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final firestore = FirebaseFirestore.instance;

      final subjectsFuture = firestore
          .collection('subjects')
          .where('active', isEqualTo: true)
          .get();

      final teacherSubjectsFuture = firestore
          .collection('teacherSubjects')
          .where(
            'teacherId',
            isEqualTo: widget.teacherId,
          )
          .get();

      final subjectsSnapshot = await subjectsFuture;
      final teacherSubjectsSnapshot = await teacherSubjectsFuture;

      final selectedIds = teacherSubjectsSnapshot.docs
          .map(
            (doc) => doc.data()['subjectId']?.toString(),
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

  Future<void> _loadAssignments() async {
    try {
      final firestore = FirebaseFirestore.instance;

      final classesFuture = firestore
          .collection('classes')
          .where('active', isEqualTo: true)
          .get();

      final assignmentsFuture = firestore
          .collection('teacherAssignments')
          .where(
            'teacherId',
            isEqualTo: widget.teacherId,
          )
          .get();

      final classesSnapshot = await classesFuture;
      final assignmentsSnapshot = await assignmentsFuture;

      final selectedIds = assignmentsSnapshot.docs
          .map((doc) {
            final data = doc.data();

            final classId = data['classId']?.toString();
            final subjectId = data['subjectId']?.toString();

            if (classId == null ||
                classId.isEmpty ||
                subjectId == null ||
                subjectId.isEmpty) {
              return null;
            }

            return '${classId}_$subjectId';
          })
          .whereType<String>()
          .toSet();

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = classesSnapshot.docs;

        _selectedAssignmentIds
          ..clear()
          ..addAll(selectedIds);

        _isLoadingAssignments = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingAssignments = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر تحميل الفصول والتكليفات: $error',
          ),
        ),
      );
    }
  }

  Future<void> _saveTeacher() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final name = _nameController.text.trim();

      final firestore = FirebaseFirestore.instance;

      final teacherSubjectsSnapshot = await firestore
          .collection('teacherSubjects')
          .where(
            'teacherId',
            isEqualTo: widget.teacherId,
          )
          .get();

      final teacherAssignmentsSnapshot = await firestore
          .collection('teacherAssignments')
          .where(
            'teacherId',
            isEqualTo: widget.teacherId,
          )
          .get();

      final batch = firestore.batch();

      final teacherRef = firestore
          .collection('teachers')
          .doc(widget.teacherId);

      final userId =
          widget.teacherData['userId']?.toString() ??
              widget.teacherId;

      final userRef = firestore
          .collection('users')
          .doc(userId);

      batch.update(teacherRef, {
        'active': _active,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(userRef, {
        'name': name,
        'active': _active,
      });

      // حذف المواد التي تم إلغاء اختيارها.
      for (final doc in teacherSubjectsSnapshot.docs) {
        final subjectId =
            doc.data()['subjectId']?.toString();

        if (subjectId == null ||
            !_selectedSubjectIds.contains(subjectId)) {
          batch.delete(doc.reference);
        }
      }

      // إضافة المواد الجديدة.
      for (final subjectId in _selectedSubjectIds) {
        final exists = teacherSubjectsSnapshot.docs.any(
          (doc) =>
              doc.data()['subjectId']?.toString() ==
              subjectId,
        );

        if (!exists) {
          final relationId =
              '${widget.teacherId}_$subjectId';

          final relationRef = firestore
              .collection('teacherSubjects')
              .doc(relationId);

          batch.set(relationRef, {
            'teacherId': widget.teacherId,
            'subjectId': subjectId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // حذف أي تكليف لم يعد موجودًا في الاختيارات.
      for (final doc in teacherAssignmentsSnapshot.docs) {
        final data = doc.data();

        final classId = data['classId']?.toString();
        final subjectId = data['subjectId']?.toString();

        if (classId == null ||
            classId.isEmpty ||
            subjectId == null ||
            subjectId.isEmpty) {
          batch.delete(doc.reference);
          continue;
        }

        final assignmentId = '${classId}_$subjectId';

        if (!_selectedAssignmentIds.contains(assignmentId) ||
            !_selectedSubjectIds.contains(subjectId)) {
          batch.delete(doc.reference);
        }
      }

      // مزامنة مالك/مدرّسي الفصل حتى يستطيع المعلم إدارة فصوله.
      final classIdsForTeacher = <String>{};
      for (final selectedId in _selectedAssignmentIds) {
        final separatorIndex = selectedId.indexOf('_');
        if (separatorIndex > 0) {
          classIdsForTeacher.add(selectedId.substring(0, separatorIndex));
        }
      }

      for (final classDoc in _classes) {
        final classId = classDoc.id;
        final classRef = firestore.collection('classes').doc(classId);
        if (classIdsForTeacher.contains(classId)) {
          batch.update(classRef, {
            'teacherIds': FieldValue.arrayUnion([widget.teacherId]),
          });
        } else {
          batch.update(classRef, {
            'teacherIds': FieldValue.arrayRemove([widget.teacherId]),
          });
        }
      }

      // إضافة التكليفات الجديدة.
      for (final assignmentId in _selectedAssignmentIds) {
        final separatorIndex = assignmentId.indexOf('_');

        if (separatorIndex <= 0 ||
            separatorIndex >= assignmentId.length - 1) {
          continue;
        }

        final classId =
            assignmentId.substring(0, separatorIndex);

        final subjectId =
            assignmentId.substring(separatorIndex + 1);

        // لا يمكن تكليف المعلم بمادة غير موجودة
        // ضمن المواد التي يدرسها.
        if (!_selectedSubjectIds.contains(subjectId)) {
          continue;
        }

        final exists = teacherAssignmentsSnapshot.docs.any(
          (doc) {
            final data = doc.data();

            return data['classId']?.toString() == classId &&
                data['subjectId']?.toString() == subjectId;
          },
        );

        if (!exists) {
          final relationId =
              '${widget.teacherId}_${classId}_$subjectId';

          final relationRef = firestore
              .collection('teacherAssignments')
              .doc(relationId);

          batch.set(relationRef, {
            'teacherId': widget.teacherId,
            'classId': classId,
            'subjectId': subjectId,
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
            'تم تحديث بيانات المعلم والمواد والتكليفات بنجاح',
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

                        // إزالة أي تكليفات لهذه المادة.
                        _selectedAssignmentIds.removeWhere(
                          (assignmentId) {
                            return assignmentId
                                    .endsWith(
                                  '_$subjectId',
                                );
                          },
                        );
                      }
                    });
                  },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAssignmentsSection() {
    if (_isLoadingAssignments) {
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
          child: Column(
            children: [
              const Icon(
                Icons.groups_outlined,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'لا توجد فصول أو مجموعات نشطة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'أضف فصلًا أو مجموعة من إدارة الفصول أولًا.',
                textAlign: TextAlign.center,
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

    if (_subjects.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'أضف مادة نشطة من إدارة المواد أولًا.',
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
        children: _classes.map((classDoc) {
          final classData = classDoc.data();

          final classId = classDoc.id;

          final className =
              classData['name']?.toString() ?? '';

          final grade =
              classData['grade']?.toString() ?? '';

          return ExpansionTile(
            leading: const Icon(
              Icons.groups_outlined,
            ),
            title: Text(
              className.isEmpty
                  ? 'فصل بدون اسم'
                  : className,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: grade.isEmpty
                ? null
                : Text('الصف: $grade'),
            children: _subjects.map((subjectDoc) {
              final subjectData = subjectDoc.data();

              final subjectId = subjectDoc.id;

              final nameAr =
                  subjectData['nameAr']?.toString() ?? '';

              final nameEn =
                  subjectData['nameEn']?.toString() ?? '';

              final assignmentId =
                  '${classId}_$subjectId';

              final subjectSelected =
                  _selectedSubjectIds.contains(subjectId);

              return CheckboxListTile(
                contentPadding:
                    const EdgeInsets.symmetric(
                  horizontal: 24,
                ),
                value: subjectSelected &&
                    _selectedAssignmentIds.contains(
                      assignmentId,
                    ),
                title: Text(
                  nameAr.isEmpty
                      ? 'مادة بدون اسم'
                      : nameAr,
                ),
                subtitle: nameEn.isEmpty
                    ? subjectSelected
                        ? null
                        : const Text(
                            'اختر المادة أولًا من قسم المواد',
                          )
                    : Text(
                        subjectSelected
                            ? nameEn
                            : '$nameEn - اختر المادة أولًا',
                      ),
                secondary: const Icon(
                  Icons.menu_book_outlined,
                ),
                onChanged: _isSaving || !subjectSelected
                    ? null
                    : (value) {
                        setState(() {
                          if (value == true) {
                            _selectedAssignmentIds.add(
                              assignmentId,
                            );
                          } else {
                            _selectedAssignmentIds.remove(
                              assignmentId,
                            );
                          }
                        });
                      },
              );
            }).toList(),
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
            'تعديل المعلم',
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
                    'بيانات المعلم',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _nameController,
                    textInputAction:
                        TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'اسم المعلم',
                      prefixIcon: Icon(
                        Icons.person_outline,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'يرجى إدخال اسم المعلم';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(
                        Icons.email_outlined,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      widget.userData['email']
                              ?.toString() ??
                          '',
                      style: const TextStyle(
                        fontSize: 16,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'المواد التي يدرسها المعلم',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _buildSubjectsSection(),

                  const SizedBox(height: 24),

                  const Text(
                    'الفصول والمجموعات التي يدرسها المعلم',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _buildAssignmentsSection(),

                  const SizedBox(height: 20),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'حساب المعلم نشط',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _active
                          ? 'المعلم يستطيع تسجيل الدخول'
                          : 'المعلم لا يستطيع تسجيل الدخول',
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
                      onPressed:
                          _isSaving ||
                                  _isLoadingSubjects ||
                                  _isLoadingAssignments
                              ? null
                              : _saveTeacher,
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
