import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firebase_auth_rest_service.dart';

class AddStudentScreen extends StatefulWidget {
  const AddStudentScreen({super.key});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _studentCodeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedClassId;

  final Set<String> _selectedSubjectIds = {};

  bool _active = true;
  bool _obscurePassword = true;
  bool _isSaving = false;

  final _authRestService = FirebaseAuthRestService();

  @override
  void dispose() {
    _nameController.dispose();
    _studentCodeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
      final studentCode = _studentCodeController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final firestore = FirebaseFirestore.instance;

      final existingStudent = await firestore
          .collection('students')
          .where(
            'studentCode',
            isEqualTo: studentCode,
          )
          .limit(1)
          .get();

      if (existingStudent.docs.isNotEmpty) {
        throw Exception('كود الطالب مستخدم بالفعل.');
      }

      final studentUid = await _authRestService.createUser(
        email: email,
        password: password,
      );

      final batch = firestore.batch();

      final userRef = firestore
          .collection('users')
          .doc(studentUid);

      final studentRef = firestore
          .collection('students')
          .doc(studentUid);

      batch.set(userRef, {
        'name': name,
        'email': email,
        'role': 'student',
        'active': _active,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.set(studentRef, {
        'userId': studentUid,
        'classId': _selectedClassId,
        'name': name,
        'studentCode': studentCode,
        'active': _active,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ربط الطالب بالمواد المختارة
      for (final subjectId in _selectedSubjectIds) {
        final studentSubjectRef = firestore
            .collection('studentSubjects')
            .doc('${studentUid}_$subjectId');

        batch.set(studentSubjectRef, {
          'studentId': studentUid,
          'subjectId': subjectId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إنشاء حساب الطالب وربطه بالمواد بنجاح',
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
    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('subjects')
          .where(
            'active',
            isEqualTo: true,
          )
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
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
                'حدث خطأ أثناء تحميل المواد',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final subjects = snapshot.data?.docs ?? [];

        if (subjects.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'لا توجد مواد نشطة. أضف مادة من إدارة المواد أولًا.',
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
            children: subjects.map((subjectDoc) {
              final data = subjectDoc.data();

              final subjectId = subjectDoc.id;

              final nameAr =
                  data['nameAr']?.toString() ?? '';

              final nameEn =
                  data['nameEn']?.toString() ?? '';

              return CheckboxListTile(
                value: _selectedSubjectIds.contains(
                  subjectId,
                ),
                secondary: const Icon(
                  Icons.menu_book_outlined,
                ),
                title: Text(
                  nameAr.isEmpty
                      ? 'مادة بدون اسم'
                      : nameAr,
                ),
                subtitle: nameEn.isEmpty
                    ? null
                    : Text(nameEn),
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
            'إضافة طالب',
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

                      return DropdownButtonFormField<String>(
                        value: _selectedClassId,
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

                  const SizedBox(height: 28),

                  const Text(
                    'بيانات تسجيل الدخول',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _emailController,
                    keyboardType:
                        TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon:
                          Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'يرجى إدخال البريد الإلكتروني';
                      }

                      if (!value.contains('@')) {
                        return 'يرجى إدخال بريد إلكتروني صحيح';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller:
                        _passwordController,
                    obscureText: _obscurePassword,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon:
                          const Icon(Icons.lock_outline),
                      border:
                          const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword =
                                !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons
                                  .visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.isEmpty) {
                        return 'يرجى إدخال كلمة المرور';
                      }

                      if (value.length < 6) {
                        return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                      }

                      return null;
                    },
                  ),

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
                            : 'حفظ الطالب',
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
