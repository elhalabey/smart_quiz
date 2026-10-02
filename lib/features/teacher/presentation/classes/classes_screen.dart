import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'add_class_screen.dart';
import 'edit_class_screen.dart';

class ClassesScreen extends StatelessWidget {
  const ClassesScreen({super.key});
  
Future<void> _deleteClass(
  BuildContext context,
  String classId,
  String className,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('حذف الفصل'),
        content: Text(
          'هل أنت متأكد من حذف الفصل "$className"؟\n\n'
          'سيتم فصل الطلاب عن الفصل وحذف تكليفات المعلمين '
          'وروابط الاختبارات بهذا الفصل.\n\n'
          'لن يتم حذف الطلاب أو المعلمين أو المواد أو الاختبارات.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('حذف'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  final firestore = FirebaseFirestore.instance;

  try {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final userSnapshot = currentUid == null
        ? null
        : await firestore.collection('users').doc(currentUid).get();
    final currentRole = userSnapshot?.data()?['role']?.toString();

    // ============================================================
    // 1. المعلمين + المواد المرتبطين بالفصل
    // ============================================================

    Query<Map<String, dynamic>> assignmentsQuery = firestore
        .collection('teacherAssignments')
        .where('classId', isEqualTo: classId);
    if (currentRole == 'teacher' && currentUid != null) {
      assignmentsQuery = assignmentsQuery.where('teacherId', isEqualTo: currentUid);
    }
    final assignmentsSnapshot = await assignmentsQuery.get();

    // ============================================================
    // 2. الطلاب الموجودون في الفصل
    // ============================================================

    final studentsSnapshot = await firestore
        .collection('students')
        .where(
          'classId',
          isEqualTo: classId,
        )
        .get();

    // ============================================================
    // 3. الاختبارات المرتبطة بالفصل
    // ============================================================

    Query<Map<String, dynamic>> quizClassesQuery = firestore
        .collection('quizClasses')
        .where('classId', isEqualTo: classId);
    if (currentRole == 'teacher' && currentUid != null) {
      quizClassesQuery = quizClassesQuery.where('teacherId', isEqualTo: currentUid);
    }
    final quizClassesSnapshot = await quizClassesQuery.get();

    // ============================================================
    // نستخدم batches صغيرة حتى لا نتجاوز حد Firestore
    // ============================================================

    const batchLimit = 400;

    final operations = <Future<void> Function(WriteBatch)>[];

    // حذف teacherAssignments
    for (final doc in assignmentsSnapshot.docs) {
      operations.add(
        (batch) async {
          batch.delete(doc.reference);
        },
      );
    }

    // فصل الطلاب عن الفصل بدون حذفهم
    for (final doc in studentsSnapshot.docs) {
      operations.add(
        (batch) async {
          batch.update(
            doc.reference,
            {
              'classId': null,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        },
      );
    }

    // حذف روابط الاختبارات بالفصل
    for (final doc in quizClassesSnapshot.docs) {
      operations.add(
        (batch) async {
          batch.delete(doc.reference);
        },
      );
    }

    // تنفيذ العمليات على دفعات
    for (var i = 0; i < operations.length; i += batchLimit) {
      final batch = firestore.batch();

      final end = (i + batchLimit < operations.length)
          ? i + batchLimit
          : operations.length;

      for (var j = i; j < end; j++) {
        await operations[j](batch);
      }

      await batch.commit();
    }

    // ============================================================
    // 4. حذف الفصل نفسه في النهاية
    // ============================================================

    await firestore
        .collection('classes')
        .doc(classId)
        .delete();

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم حذف الفصل "$className" بنجاح',
        ),
      ),
    );
  } on FirebaseException catch (e) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'حدث خطأ أثناء حذف الفصل:\n'
          '${e.message ?? e.code}',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'حدث خطأ أثناء حذف الفصل:\n$e',
        ),
      ),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الفصول والمجموعات'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AddClassScreen(),
              ),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('إضافة فصل'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('classes')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'تعذر تحميل الفصول والمجموعات:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(
                child: Text('لا توجد فصول أو مجموعات حاليًا'),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();

                final name = data['name']?.toString() ?? '';
                final grade = data['grade']?.toString() ?? '';
                final active = data['active'] == true;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditClassScreen(
                            classId: doc.id,
                            classData: data,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            child: Icon(
                              Icons.groups,
                              color: active ? null : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? 'بدون اسم' : name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (grade.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('الصف: $grade'),
                                ],
                              ],
                            ),
                          ),
                          Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(
      active
          ? Icons.check_circle
          : Icons.cancel,
      color: active ? Colors.green : Colors.red,
    ),
    const SizedBox(width: 4),
    PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'delete') {
          _deleteClass(
            context,
            doc.id,
            name.isEmpty ? 'بدون اسم' : name,
          );
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: Colors.red,
              ),
              SizedBox(width: 8),
              Text('حذف الفصل'),
            ],
          ),
        ),
      ],
    ),
  ],
),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
