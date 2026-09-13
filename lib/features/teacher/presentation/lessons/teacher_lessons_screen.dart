import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';

class TeacherLessonsScreen extends StatefulWidget {
  final SessionManager sessionManager;

  const TeacherLessonsScreen({
    super.key,
    required this.sessionManager,
  });

  @override
  State<TeacherLessonsScreen> createState() => _TeacherLessonsScreenState();
}

class _TeacherLessonsScreenState extends State<TeacherLessonsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedSubjectId;
  bool _loadingSubjects = true;
  List<_TeacherSubject> _subjects = [];

  String get _teacherId => widget.sessionManager.currentSession!.uid;

  @override
  void initState() {
    super.initState();
    _loadTeacherSubjects();
  }

  Future<void> _loadTeacherSubjects() async {
    try {
      final teacherSubjectsSnapshot = await _firestore
          .collection('teacherSubjects')
          .where('teacherId', isEqualTo: _teacherId)
          .get();

      final subjectIds = teacherSubjectsSnapshot.docs
          .map((doc) => doc.data()['subjectId']?.toString())
          .whereType<String>()
          .toSet();

      if (subjectIds.isEmpty) {
        if (mounted) {
          setState(() {
            _subjects = [];
            _selectedSubjectId = null;
            _loadingSubjects = false;
          });
        }
        return;
      }

      final subjectsSnapshot = await _firestore.collection('subjects').get();

      final subjects = subjectsSnapshot.docs
          .where((doc) {
            final data = doc.data();
            final subjectId = doc.id;
            final active = data['active'] != false;

            return active && subjectIds.contains(subjectId);
          })
          .map(
            (doc) => _TeacherSubject(
              id: doc.id,
              nameAr: doc.data()['nameAr']?.toString() ?? '',
              nameEn: doc.data()['nameEn']?.toString() ?? '',
            ),
          )
          .toList();

      subjects.sort(
        (a, b) => a.nameAr.compareTo(b.nameAr),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _subjects = subjects;
        _selectedSubjectId =
            subjects.isNotEmpty ? subjects.first.id : null;
        _loadingSubjects = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingSubjects = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تحميل المواد: $e'),
        ),
      );
    }
  }

  Future<bool> _isTeacherAssignedToSubject(String subjectId) async {
    final doc = await _firestore
        .collection('teacherSubjects')
        .doc('${_teacherId}_$subjectId')
        .get();

    return doc.exists;
  }

  Future<int> _getNextLessonOrder(String subjectId) async {
    final snapshot = await _firestore
        .collection('lessons')
        .where('teacherId', isEqualTo: _teacherId)
        .where('subjectId', isEqualTo: subjectId)
        .get();

    var maxOrder = 0;

    for (final doc in snapshot.docs) {
      final value = doc.data()['order'];

      if (value is num) {
        final order = value.toInt();

        if (order > maxOrder) {
          maxOrder = order;
        }
      }
    }

    return maxOrder + 1;
  }

  Future<void> _showLessonForm({
    DocumentSnapshot<Map<String, dynamic>>? lessonDoc,
  }) async {
    final isEditing = lessonDoc != null;
    final data = lessonDoc?.data() ?? {};

    String? subjectId = isEditing
        ? data['subjectId']?.toString()
        : _selectedSubjectId;

    final titleController = TextEditingController(
      text: data['title']?.toString() ?? '',
    );

    final contentController = TextEditingController(
      text: data['content']?.toString() ?? '',
    );

    bool active = data['active'] != false;
    bool saving = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !saving,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> save() async {
                final title = titleController.text.trim();
                final content = contentController.text.trim();

                final selectedSubjectId = subjectId;

                if (selectedSubjectId == null ||
                    selectedSubjectId.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('اختر المادة أولًا'),
                    ),
                  );
                  return;
                }

                if (title.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('اكتب عنوان الدرس'),
                    ),
                  );
                  return;
                }

                if (content.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('اكتب محتوى الدرس'),
                    ),
                  );
                  return;
                }

                setDialogState(() {
                  saving = true;
                });

                try {
                  final assigned = await _isTeacherAssignedToSubject(
                    selectedSubjectId,
                  );

                  if (!assigned) {
                    if (dialogContext.mounted) {
                      setDialogState(() {
                        saving = false;
                      });

                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'أنت غير مكلّف بتدريس هذه المادة',
                          ),
                        ),
                      );
                    }
                    return;
                  }

                  if (isEditing) {
                    final oldSubjectId =
                        data['subjectId']?.toString();

                    int order =
                        (data['order'] as num?)?.toInt() ?? 0;

                    // لو الدرس قديم وليس له ترتيب صحيح،
                    // نحسب له ترتيبًا تلقائيًا.
                    if (order < 1) {
                      order = await _getNextLessonOrder(
                        selectedSubjectId,
                      );
                    }

                    // لو تم تغيير المادة أثناء التعديل،
                    // نضع الدرس في نهاية المادة الجديدة.
                    if (oldSubjectId != selectedSubjectId) {
                      order = await _getNextLessonOrder(
                        selectedSubjectId,
                      );
                    }

                    await _firestore
                        .collection('lessons')
                        .doc(lessonDoc.id)
                        .update({
                      'subjectId': selectedSubjectId,
                      'teacherId': _teacherId,
                      'title': title,
                      'content': content,
                      'order': order,
                      'active': active,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                  } else {
                    final order = await _getNextLessonOrder(
                      selectedSubjectId,
                    );

                    await _firestore.collection('lessons').add({
                      'subjectId': selectedSubjectId,
                      'teacherId': _teacherId,
                      'title': title,
                      'content': content,
                      'order': order,
                      'active': active,
                      'createdAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                  }

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEditing
                              ? 'تم تعديل الدرس بنجاح'
                              : 'تم إضافة الدرس بنجاح',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  setDialogState(() {
                    saving = false;
                  });

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text('حدث خطأ أثناء حفظ الدرس: $e'),
                    ),
                  );
                }
              }

              return Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                  title: Text(
                    isEditing ? 'تعديل الدرس' : 'إضافة درس',
                  ),
                  content: SingleChildScrollView(
                    child: SizedBox(
                      width: 500,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            value: subjectId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'المادة',
                              border: OutlineInputBorder(),
                            ),
                            items: _subjects.map((subject) {
                              return DropdownMenuItem<String>(
                                value: subject.id,
                                child: Text(
                                  subject.nameAr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: saving
                                ? null
                                : (value) {
                                    setDialogState(() {
                                      subjectId = value;
                                    });
                                  },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: titleController,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'عنوان الدرس',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: contentController,
                            enabled: !saving,
                            minLines: 5,
                            maxLines: 10,
                            decoration: const InputDecoration(
                              labelText: 'محتوى الدرس',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('الدرس نشط'),
                            value: active,
                            onChanged: saving
                                ? null
                                : (value) {
                                    setDialogState(() {
                                      active = value;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      onPressed: saving ? null : save,
                      child: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              isEditing ? 'حفظ التعديل' : 'إضافة',
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      contentController.dispose();
    }
  }

  Future<void> _deleteLesson(
    DocumentSnapshot<Map<String, dynamic>> lessonDoc,
  ) async {
    final data = lessonDoc.data() ?? {};
    final title = data['title']?.toString() ?? 'هذا الدرس';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('حذف الدرس'),
            content: Text(
              'هل أنت متأكد من حذف "$title"؟',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _firestore
          .collection('lessons')
          .doc(lessonDoc.id)
          .delete();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الدرس بنجاح'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء حذف الدرس: $e'),
        ),
      );
    }
  }

  Future<void> _reorderLessons(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> lessons,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final reordered = List<
        QueryDocumentSnapshot<Map<String, dynamic>>>.from(lessons);

    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    final batch = _firestore.batch();

    for (var index = 0; index < reordered.length; index++) {
      batch.update(
        reordered[index].reference,
        {
          'order': index + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }

    try {
      await batch.commit();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث ترتيب الدروس'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء ترتيب الدروس: $e'),
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
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'لا توجد مواد مكلّف بها هذا المعلم.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Card(
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
                subject.nameAr,
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
        stream: _firestore
            .collection('lessons')
            .where('teacherId', isEqualTo: _teacherId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'حدث خطأ أثناء تحميل الدروس:\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final lessons = snapshot.data?.docs
                  .where((doc) {
                    final data = doc.data();
                    return data['subjectId']?.toString() ==
                        subjectId;
                  })
                  .toList() ??
              [];

          lessons.sort((a, b) {
            final orderA =
                (a.data()['order'] as num?)?.toInt() ?? 0;
            final orderB =
                (b.data()['order'] as num?)?.toInt() ?? 0;

            if (orderA != orderB) {
              return orderA.compareTo(orderB);
            }

            final createdA =
                a.data()['createdAt'] as Timestamp?;
            final createdB =
                b.data()['createdAt'] as Timestamp?;

            if (createdA == null && createdB == null) {
              return 0;
            }

            if (createdA == null) {
              return 1;
            }

            if (createdB == null) {
              return -1;
            }

            return createdA.compareTo(createdB);
          });

          if (lessons.isEmpty) {
            return RefreshIndicator(
              onRefresh: _loadTeacherSubjects,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'لا توجد دروس في هذه المادة حتى الآن.',
                    ),
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.only(
              left: 8,
              right: 8,
              bottom: 90,
            ),
            itemCount: lessons.length,
            onReorder: (oldIndex, newIndex) {
              _reorderLessons(
                lessons,
                oldIndex,
                newIndex,
              );
            },
            itemBuilder: (context, index) {
              final lesson = lessons[index];
              final data = lesson.data();

              final title =
                  data['title']?.toString() ?? 'بدون عنوان';

              final content =
                  data['content']?.toString() ?? '';

              final order =
                  (data['order'] as num?)?.toInt() ?? index + 1;

              final active = data['active'] != false;

              return Card(
                key: ValueKey(lesson.id),
                margin: const EdgeInsets.symmetric(
                  vertical: 5,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    child: Text(
                      '$order',
                    ),
                  ),
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        if (content.isNotEmpty)
                          Text(
                            content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 5),
                        Text(
                          active ? 'نشط' : 'غير نشط',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: active
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showLessonForm(
                          lessonDoc: lesson,
                        );
                      } else if (value == 'delete') {
                        _deleteLesson(lesson);
                      }
                    },
                    itemBuilder: (context) {
                      return const [
                        PopupMenuItem<String>(
                          value: 'edit',
                          child: Text('تعديل الدرس'),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('حذف الدرس'),
                        ),
                      ];
                    },
                  ),
                ),
              );
            },
          );
        },
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
              const SizedBox(height: 8),
              if (_subjects.isNotEmpty)
                Expanded(
                  child: _buildLessonsList(),
                )
              else
                const Expanded(
                  child: Center(
                    child: Text(
                      'لا توجد مواد مرتبطة بهذا المعلم.',
                    ),
                  ),
                ),
            ],
          ),
        ),
        floatingActionButton: _subjects.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showLessonForm(),
                icon: const Icon(Icons.add),
                label: const Text('إضافة درس'),
              ),
      ),
    );
  }
}

class _TeacherSubject {
  final String id;
  final String nameAr;
  final String nameEn;

  const _TeacherSubject({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });
}
