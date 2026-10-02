
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';
import 'add_teacher_question_screen.dart';
import 'edit_teacher_question_screen.dart';
import 'exam_print_service.dart';

class TeacherQuestionsScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final String quizId;
  final String quizTitle;
  final String subjectId;

  const TeacherQuestionsScreen({
    super.key,
    required this.sessionManager,
    required this.quizId,
    required this.quizTitle,
    required this.subjectId,
  });

  @override
  State<TeacherQuestionsScreen> createState() =>
      _TeacherQuestionsScreenState();
}

class _TeacherQuestionsScreenState
    extends State<TeacherQuestionsScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  bool _loading = false;
  bool _reordering = false;

  /// جلب اسم المادة العربي من:
  /// subjects/{subjectId}
  ///
  /// والاعتماد على field:
  /// nameAr
  Future<String> _loadSubjectName() async {
    final subjectId = widget.subjectId.trim();

    if (subjectId.isEmpty) {
      return 'غير محددة';
    }

    try {
      final subjectDoc = await _firestore
          .collection('subjects')
          .doc(subjectId)
          .get();

      if (!subjectDoc.exists) {
        return subjectId;
      }

      final data = subjectDoc.data();

      if (data == null) {
        return subjectId;
      }

      final nameAr = data['nameAr']?.toString().trim();

      if (nameAr != null && nameAr.isNotEmpty) {
        return nameAr;
      }

      return subjectId;
    } catch (_) {
      // في حالة حدوث مشكلة في جلب المادة،
      // نرجع الـ ID بدل توقف عملية الطباعة بالكامل.
      return subjectId;
    }
  }

  Future<List<_TeacherQuestionItem>> _loadQuestions() async {
    final quizQuestionsSnapshot = await _firestore
        .collection('quizQuestions')
        .where(
          'quizId',
          isEqualTo: widget.quizId,
        )
        .get();

    final items = <_TeacherQuestionItem>[];

    for (final relationDoc in quizQuestionsSnapshot.docs) {
      final relationData = relationDoc.data();

      final questionId =
          relationData['questionId']?.toString();

      if (questionId == null || questionId.isEmpty) {
        continue;
      }

      final questionDoc = await _firestore
          .collection('questions')
          .doc(questionId)
          .get();

      if (!questionDoc.exists) {
        continue;
      }

      final questionData = questionDoc.data();

      if (questionData == null) {
        continue;
      }

      items.add(
        _TeacherQuestionItem(
          relationId: relationDoc.id,
          questionId: questionId,
          order: _readOrder(
            relationData['order'],
          ),
          data: questionData,
        ),
      );
    }

    items.sort(
      (a, b) => a.order.compareTo(b.order),
    );

    return items;
  }

  int _readOrder(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return 0;
  }

  String _questionTypeLabel(String? type) {
    switch (type) {
      case 'single_choice':
        return 'اختيار من متعدد';

      case 'multiple_choice':
        return 'اختيار متعدد';

      case 'true_false':
        return 'صح / خطأ';

      case 'essay':
        return 'مقالي';

      case 'ordering':
        return 'ترتيب';

      default:
        return 'غير محدد';
    }
  }

  Future<void> _printExam() async {
    if (_loading || _reordering) {
      return;
    }

    try {
      final items = await _loadQuestions();

      if (items.isEmpty) {
        if (!mounted) return;

        _showMessage(
          'لا توجد أسئلة داخل الاختبار للطباعة.',
        );

        return;
      }

      // جلب اسم المادة من subjects باستخدام subjectId
      final subjectName = await _loadSubjectName();

      final questions = <PrintQuestion>[];

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final data = item.data;

        final rawOptions = data['options'];

        final options = rawOptions is Iterable
            ? rawOptions
                .map(
                  (option) => option.toString(),
                )
                .toList()
            : <String>[];

        final scoreValue = data['score'];

        final score = scoreValue is num
            ? scoreValue.toDouble()
            : double.tryParse(
                  scoreValue?.toString() ?? '',
                ) ??
                1.0;

        questions.add(
          PrintQuestion(
            number: i + 1,
            text: data['text']?.toString() ?? '',
            type: data['type']?.toString() ?? '',
            options: options,
            score: score,
          ),
        );
      }

      await printExam(
        title: widget.quizTitle,

        // اسم المادة العربي بدل الـ subjectId
        subject: subjectName,

        questions: questions,
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        'تعذر طباعة الامتحان:\n$error',
      );
    }
  }

  Future<void> _addQuestion() async {
    if (_loading) {
      return;
    }

    final questionId =
        await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AddTeacherQuestionScreen(
          sessionManager: widget.sessionManager,
          quizId: widget.quizId,
          quizTitle: widget.quizTitle,
          subjectId: widget.subjectId,
        ),
      ),
    );

    if (!mounted || questionId == null) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final existingSnapshot = await _firestore
          .collection('quizQuestions')
          .where(
            'quizId',
            isEqualTo: widget.quizId,
          )
          .get();

      var nextOrder = 1;

      for (final doc in existingSnapshot.docs) {
        final order = _readOrder(
          doc.data()['order'],
        );

        if (order >= nextOrder) {
          nextOrder = order + 1;
        }
      }

      final relationId =
          '${widget.quizId}_$questionId';

      await _firestore
          .collection('quizQuestions')
          .doc(relationId)
          .set({
        'quizId': widget.quizId,
        'questionId': questionId,
        'order': nextOrder,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      _showMessage(
        'تمت إضافة السؤال إلى الاختبار',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'حدث خطأ أثناء إضافة السؤال:\n$error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _editQuestion(
    _TeacherQuestionItem item,
  ) async {
    if (_reordering) {
      return;
    }

    final updated =
        await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditTeacherQuestionScreen(
          sessionManager: widget.sessionManager,
          questionId: item.questionId,
          quizId: widget.quizId,
          quizTitle: widget.quizTitle,
          subjectId: widget.subjectId,
          questionData: item.data,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (updated == true) {
      setState(() {});
    }
  }

  Future<void> _deleteQuestion(
    _TeacherQuestionItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'حذف السؤال من الاختبار',
          ),
          content: const Text(
            'سيتم حذف السؤال من هذا الاختبار فقط، ولن يتم حذف السؤال من بنك الأسئلة.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  false,
                );
              },
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  true,
                );
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

    try {
      await _firestore
          .collection('quizQuestions')
          .doc(item.relationId)
          .delete();

      if (!mounted) {
        return;
      }

      _showMessage(
        'تم حذف السؤال من الاختبار',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'حدث خطأ أثناء حذف السؤال:\n$error',
      );
    }
  }

  Future<void> _reorderQuestions(
    List<_TeacherQuestionItem> items,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reordering) {
      return;
    }

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    setState(() {
      _reordering = true;
    });

    try {
      final batch = _firestore.batch();

      for (var index = 0;
          index < items.length;
          index++) {
        batch.update(
          _firestore
              .collection('quizQuestions')
              .doc(items[index].relationId),
          {
            'order': index + 1,
          },
        );
      }

      await batch.commit();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'حدث خطأ أثناء ترتيب الأسئلة:\n$error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _reordering = false;
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

  Widget _buildQuestionCard(
    BuildContext context,
    _TeacherQuestionItem item,
    int index,
  ) {
    final data = item.data;

    final text =
        data['text']?.toString() ?? '';

    final type =
        data['type']?.toString();

    final score =
        data['score']?.toString() ?? '1';

    return Card(
      key: ValueKey(item.relationId),
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            '${index + 1}',
          ),
        ),
        title: Text(
          text.isEmpty
              ? 'سؤال بدون نص'
              : text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(
            top: 6,
          ),
          child: Text(
            '${_questionTypeLabel(type)} • الدرجة: $score',
          ),
        ),
        trailing: PopupMenuButton<String>(
          enabled: !_reordering,
          onSelected: (value) {
            if (value == 'edit') {
              _editQuestion(item);
            } else if (value == 'delete') {
              _deleteQuestion(item);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem<String>(
              value: 'edit',
              child: Text(
                'تعديل السؤال',
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Text(
                'حذف من الاختبار',
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
            'أسئلة الاختبار',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'طباعة الامتحان',
              onPressed:
                  _loading || _reordering
                      ? null
                      : _printExam,
              icon: const Icon(
                Icons.print_outlined,
              ),
            ),
          ],
        ),
        body: FutureBuilder<List<_TeacherQuestionItem>>(
          future: _loadQuestions(),
          builder: (
            context,
            snapshot,
          ) {
            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'حدث خطأ أثناء تحميل الأسئلة:\n${snapshot.error}',
                    textAlign:
                        TextAlign.center,
                  ),
                ),
              );
            }

            final items =
                snapshot.data ??
                    <_TeacherQuestionItem>[];

            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.quiz_outlined,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      const Text(
                        'لا توجد أسئلة في هذا الاختبار',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                        textAlign:
                            TextAlign.center,
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      Text(
                        'اضغط على زر إضافة سؤال لإنشاء أول سؤال.',
                        textAlign:
                            TextAlign.center,
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

            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.quizTitle,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${items.length} سؤال',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_reordering)
                  const LinearProgressIndicator(),
                Expanded(
                  child: ReorderableListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      100,
                    ),
                    itemCount: items.length,
                    onReorder:
                        (oldIndex, newIndex) {
                      _reorderQuestions(
                        items,
                        oldIndex,
                        newIndex,
                      );
                    },
                    itemBuilder: (
                      context,
                      index,
                    ) {
                      return _buildQuestionCard(
                        context,
                        items[index],
                        index,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
        floatingActionButton:
            FloatingActionButton.extended(
          onPressed:
              _loading ? null : _addQuestion,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(
                  Icons.add,
                ),
          label: const Text(
            'إضافة سؤال',
          ),
        ),
      ),
    );
  }
}

class _TeacherQuestionItem {
  final String relationId;
  final String questionId;
  final int order;
  final Map<String, dynamic> data;

  const _TeacherQuestionItem({
    required this.relationId,
    required this.questionId,
    required this.order,
    required this.data,
  });
}


