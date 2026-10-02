import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EditClassScreen extends StatefulWidget {
  final String classId;
  final Map<String, dynamic> classData;

  const EditClassScreen({
    super.key,
    required this.classId,
    required this.classData,
  });

  @override
  State<EditClassScreen> createState() => _EditClassScreenState();
}

class _EditClassScreenState extends State<EditClassScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _gradeController = TextEditingController();

  bool _active = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _nameController.text = widget.classData['name']?.toString() ?? '';
    _gradeController.text = widget.classData['grade']?.toString() ?? '';
    _active = widget.classData['active'] == true;
  }

  Future<void> _saveClass() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;

      final name = _nameController.text.trim();
      final grade = _gradeController.text.trim();

      final existingClass = await firestore
          .collection('classes')
          .where('name', isEqualTo: name)
          .get();

      for (final doc in existingClass.docs) {
        if (doc.id != widget.classId) {
          throw Exception('اسم الفصل أو المجموعة مستخدم بالفعل.');
        }
      }

      final teacherId = FirebaseAuth.instance.currentUser?.uid;
      final updateData = <String, dynamic>{
        'name': name,
        'grade': grade,
        'active': _active,
        'updatedAt': FieldValue.serverTimestamp(),
        if (teacherId != null) 'teacherId': teacherId,
        if (teacherId != null) 'teacherIds': FieldValue.arrayUnion([teacherId]),
      };

      await firestore
          .collection('classes')
          .doc(widget.classId)
          .update(updateData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث الفصل أو المجموعة بنجاح'),
        ),
      );

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر تحديث الفصل: '
            '${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gradeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تعديل الفصل أو المجموعة'),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الفصل أو المجموعة',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال اسم الفصل أو المجموعة';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gradeController,
                decoration: const InputDecoration(
                  labelText: 'الصف',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الفصل نشط'),
                value: _active,
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() => _active = value);
                      },
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveClass,
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('حفظ التعديلات'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
