import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_question_screen.dart';
import 'edit_question_screen.dart';

class QuestionsScreen extends StatefulWidget {
  final String quizId;
  final String quizTitle;
  final Map<String, dynamic> quizData;

  const QuestionsScreen({
    super.key,
    required this.quizId,
    required this.quizTitle,
    required this.quizData,
  });

  @override
  State<QuestionsScreen> createState() =>
      _QuestionsScreenState();
}

class _QuestionsScreenState
    extends State<QuestionsScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  bool _reordering = false;

  String _typeLabel(String type) {
    switch (type) {
      case 'essay':
        return 'مقالي';

      case 'true_false':
        return 'صح / خطأ';

      case 'single_choice':
        return 'اختيار من متعدد';

      case 'multiple_choice':
        return 'اختيار متعدد';

      case 'ordering':
        return 'ترتيب';

      default:
        return type;
    }
  }

  Future<void> _deleteQuestionFromQuiz(
    String questionId,
    String questionText,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'حذف السؤال من الاختبار',
          ),
          content: Text(
            'هل تريد حذف هذا السؤال من الاختبار؟\n\n'
            '$questionText\n\n'
            'سيتم حذف ارتباط السؤال بهذا الاختبار فقط، '
            'ولن يتم حذف السؤال الأصلي أو الإجابة الصحيحة.',
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
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _firestore
          .collection('quizQuestions')
          .doc(
            '${widget.quizId}_$questionId',
          )
          .delete();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم حذف السؤال من الاختبار بنجاح',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ أثناء حذف السؤال:\n$e',
          ),
        ),
      );
    }
  }

  Future<void> _openEditQuestion(
    Map<String, dynamic> linkData,
  ) async {
    final questionId =
        linkData['questionId']?.toString();

    if (questionId == null ||
        questionId.isEmpty) {
      return;
    }

    final questionDoc = await _firestore
        .collection('questions')
        .doc(questionId)
        .get();

    if (!mounted) {
      return;
    }

    if (!questionDoc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'السؤال الأصلي غير موجود',
          ),
        ),
      );
      return;
    }

    final questionData =
        questionDoc.data() ?? {};

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditQuestionScreen(
          quizId: widget.quizId,
          quizTitle: widget.quizTitle,
          questionId: questionId,
          questionData: questionData,
          linkData: linkData,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _loadQuestion(
    String questionId,
  ) async {
    final doc = await _firestore
        .collection('questions')
        .doc(questionId)
        .get();

    if (!doc.exists) {
      return null;
    }

    return doc.data();
  }

  Future<void> _saveNewOrder(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>
        docs,
  ) async {
    if (docs.isEmpty) {
      return;
    }

    setState(() {
      _reordering = true;
    });

    try {
      final batch = _firestore.batch();

      for (int index = 0;
          index < docs.length;
          index++) {
        final doc = docs[index];

        final order = index + 1;

        batch.update(
          doc.reference,
          {
            'order': order,
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
            'تم حفظ ترتيب الأسئلة بنجاح',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ أثناء حفظ الترتيب:\n$e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _reordering = false;
        });
      }
    }
  }

  Widget _buildQuestionCard(
    QueryDocumentSnapshot<Map<String, dynamic>>
        linkDoc,
  ) {
    final linkData = linkDoc.data();

    final questionId =
        linkData['questionId']?.toString() ?? '';

    final order =
        (linkData['order'] as num?)?.toInt() ?? 0;

    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey(
        'question_$questionId',
      ),
      future: _loadQuestion(questionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text('$order'),
              ),
              title: const Text(
                'جاري تحميل السؤال...',
              ),
            ),
          );
        }

        final questionData = snapshot.data;

        if (questionData == null) {
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text('$order'),
              ),
              title: const Text(
                'السؤال غير موجود',
              ),
              subtitle: Text(
                'Question ID: $questionId',
              ),
              trailing: Row(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip:
                        'حذف من الاختبار',
                    icon: const Icon(
                      Icons.delete_outline,
                    ),
                    onPressed:
                        _reordering
                            ? null
                            : () {
                                _deleteQuestionFromQuiz(
                                  questionId,
                                  'السؤال غير الموجود',
                                );
                              },
                  ),
                  const Icon(
                    Icons.drag_handle,
                  ),
                ],
              ),
            ),
          );
        }

        final text =
            questionData['text']?.toString() ?? '';

        final type =
            questionData['type']?.toString() ?? '';

        final score =
            (questionData['score'] as num?) ?? 0;

        return Card(
          margin: const EdgeInsets.only(
            bottom: 10,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ListTile(
              leading: CircleAvatar(
                child: Text('$order'),
              ),
              title: Text(
                text.isEmpty
                    ? 'بدون نص'
                    : text,
                maxLines: 3,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              subtitle: Padding(
                padding:
                    const EdgeInsets.only(
                  top: 8,
                ),
                child: Text(
                  '${_typeLabel(type)}  •  الدرجة: $score',
                ),
              ),
              trailing: Row(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    tooltip:
                        'إدارة السؤال',
                    enabled: !_reordering,
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openEditQuestion(
                          linkData,
                        );
                      } else if (value ==
                          'delete') {
                        _deleteQuestionFromQuiz(
                          questionId,
                          text,
                        );
                      }
                    },
                    itemBuilder:
                        (context) => const [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(
                              Icons
                                  .edit_outlined,
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            Text(
                              'تعديل السؤال',
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons
                                  .delete_outline,
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            Text(
                              'حذف من الاختبار',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.drag_handle,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuestionsList() {
    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('quizQuestions')
          .where(
            'quizId',
            isEqualTo: widget.quizId,
          )
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child:
                CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding:
                  const EdgeInsets.all(24),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'حدث خطأ أثناء تحميل الأسئلة',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error
                        .toString(),
                    textAlign:
                        TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final docs =
            List<QueryDocumentSnapshot<
                Map<String, dynamic>>>.from(
          snapshot.data?.docs ?? [],
        );

        docs.sort((a, b) {
          final orderA =
              (a.data()['order']
                          as num?)
                      ?.toInt() ??
                  0;

          final orderB =
              (b.data()['order']
                          as num?)
                      ?.toInt() ??
                  0;

          return orderA.compareTo(
            orderB,
          );
        });

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding:
                  const EdgeInsets.all(32),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.quiz_outlined,
                    size: 64,
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  const Text(
                    'لا توجد أسئلة في هذا الاختبار',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'اضغط على زر + لإضافة أول سؤال.',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      )
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ReorderableListView.builder(
          padding:
              const EdgeInsets.all(16),
          itemCount: docs.length,
          buildDefaultDragHandles: true,
          onReorder: _reordering
              ? (oldIndex, newIndex) {}
              : (oldIndex, newIndex) async {
                  if (oldIndex == newIndex) {
                    return;
                  }

                  final reordered =
                      List<
                          QueryDocumentSnapshot<
                              Map<String, dynamic>>>.from(
                    docs,
                  );

                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }

                  final item =
                      reordered.removeAt(
                    oldIndex,
                  );

                  reordered.insert(
                    newIndex,
                    item,
                  );

                  await _saveNewOrder(
                    reordered,
                  );
                },
          itemBuilder:
              (context, index) {
            return KeyedSubtree(
              key: ValueKey(
                docs[index].id,
              ),
              child: _buildQuestionCard(
                docs[index],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إدارة أسئلة الاختبار',
            style: TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            if (_reordering)
              const Padding(
                padding:
                    EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: Center(
                  child:
                      SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width:
                  double.infinity,
              padding:
                  const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                12,
              ),
              child: Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  child: Text(
                    widget.quizTitle,
                    style:
                        const TextStyle(
                      fontSize: 19,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child:
                  _buildQuestionsList(),
            ),
          ],
        ),
        floatingActionButton:
            FloatingActionButton.extended(
          onPressed: _reordering
              ? null
              : () async {
                  await Navigator.of(
                    context,
                  ).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AddQuestionScreen(
                        quizId:
                            widget.quizId,
                        quizTitle:
                            widget.quizTitle,
                        quizData:
                            widget.quizData,
                      ),
                    ),
                  );
                },
          icon: const Icon(
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
