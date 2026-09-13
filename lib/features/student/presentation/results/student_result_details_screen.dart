import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';

class StudentResultDetailsScreen extends StatefulWidget {
  const StudentResultDetailsScreen({
    super.key,
    required this.sessionManager,
    required this.resultId,
  });

  final SessionManager sessionManager;
  final String resultId;

  @override
  State<StudentResultDetailsScreen> createState() =>
      _StudentResultDetailsScreenState();
}

class _StudentResultDetailsScreenState
    extends State<StudentResultDetailsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  String _quizTitle = 'الاختبار';
  double _totalScore = 0;
  double _maxScore = 0;
  double _autoScore = 0;
  double _manualScore = 0;

  final List<_StudentQuestionResult> _questions = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final studentId = widget.sessionManager.currentSession?.uid;

    if (studentId == null || studentId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'لم يتم العثور على حساب الطالب.';
      });
      return;
    }

    try {
      final resultDoc = await _firestore
          .collection('results')
          .doc(widget.resultId)
          .get();

      if (!resultDoc.exists) {
        throw Exception('النتيجة غير موجودة.');
      }

      final resultData = resultDoc.data();
      if (resultData == null) {
        throw Exception('تعذر قراءة بيانات النتيجة.');
      }

      if (resultData['studentId'] != studentId) {
        throw Exception('لا يمكنك عرض هذه النتيجة.');
      }

      if (resultData['status'] != 'published') {
        throw Exception('هذه النتيجة لم يتم نشرها بعد.');
      }

      final quizId = resultData['quizId']?.toString();
      final attemptId = resultData['attemptId']?.toString();

      if (quizId == null || quizId.isEmpty) {
        throw Exception('بيانات الاختبار غير مكتملة.');
      }

      if (attemptId == null || attemptId.isEmpty) {
        throw Exception('بيانات المحاولة غير مكتملة.');
      }

      _totalScore = _toDouble(resultData['totalScore']);
      _maxScore = _toDouble(resultData['maxScore']);
      _autoScore = _toDouble(resultData['autoScore']);
      _manualScore = _toDouble(resultData['manualScore']);

      final questionScores = _readQuestionScores(resultData['questionScores']);

      final quizDoc = await _firestore.collection('quizzes').doc(quizId).get();
      if (quizDoc.exists) {
        final quizData = quizDoc.data();
        if (quizData != null && quizData['title'] != null) {
          _quizTitle = quizData['title'].toString();
        }
      }

      final linksSnapshot = await _firestore
          .collection('quizQuestions')
          .where('quizId', isEqualTo: quizId)
          .get();

      final links = linksSnapshot.docs.toList()
        ..sort((a, b) {
          final aOrder = _toInt(a.data()['order']);
          final bOrder = _toInt(b.data()['order']);
          return aOrder.compareTo(bOrder);
        });

      final answersSnapshot = await _firestore
          .collection('answers')
          .where('attemptId', isEqualTo: attemptId)
          .where('studentId', isEqualTo: studentId)
          .get();

      final answersByQuestionId = <String, dynamic>{};
      for (final answerDoc in answersSnapshot.docs) {
        final data = answerDoc.data();
        final questionId = data['questionId']?.toString();
        if (questionId != null && questionId.isNotEmpty) {
          answersByQuestionId[questionId] = data['answer'];
        }
      }

      final loadedQuestions = <_StudentQuestionResult>[];

      for (final linkDoc in links) {
        final linkData = linkDoc.data();
        final questionId = linkData['questionId']?.toString();

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

        final type = questionData['type']?.toString() ?? '';
        final text = questionData['text']?.toString() ?? '';
        final maxScore = _toDouble(questionData['score']);

        loadedQuestions.add(
          _StudentQuestionResult(
            order: _toInt(linkData['order']),
            questionId: questionId,
            type: type,
            text: text,
            studentAnswer: answersByQuestionId[questionId],
            earnedScore: questionScores[questionId],
            maxScore: maxScore,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _questions
          ..clear()
          ..addAll(loadedQuestions);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Map<String, double> _readQuestionScores(dynamic value) {
    if (value is! Map) {
      return {};
    }

    final result = <String, double>{};
    for (final entry in value.entries) {
      result[entry.key.toString()] = _toDouble(entry.value);
    }
    return result;
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return 'حدث خطأ أثناء تحميل تفاصيل النتيجة.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل النتيجة'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadDetails();
                },
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final percentage = _maxScore > 0
        ? (_totalScore / _maxScore) * 100
        : 0.0;

    return RefreshIndicator(
      onRefresh: _loadDetails,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(percentage),
          const SizedBox(height: 16),
          if (_questions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'لا توجد أسئلة متاحة لعرض تفاصيلها.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ..._questions.map(_buildQuestionCard),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(double percentage) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _quizTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _summaryItem(
                    'الدرجة النهائية',
                    '${_formatScore(_totalScore)} / ${_formatScore(_maxScore)}',
                  ),
                ),
                Expanded(
                  child: _summaryItem(
                    'النسبة',
                    '${percentage.toStringAsFixed(1)}%',
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _summaryItem(
                    'التصحيح التلقائي',
                    _formatScore(_autoScore),
                  ),
                ),
                Expanded(
                  child: _summaryItem(
                    'التصحيح اليدوي',
                    _formatScore(_manualScore),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(_StudentQuestionResult question) {
    final hasScore = question.earnedScore != null;
    final earnedScore = question.earnedScore ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text('${question.order}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question.text.isEmpty
                        ? 'نص السؤال غير متاح.'
                        : question.text,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'إجابتك',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatStudentAnswer(question.studentAnswer),
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text(
                  'الدرجة: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  hasScore
                      ? '${_formatScore(earnedScore)} / ${_formatScore(question.maxScore)}'
                      : 'غير متاحة',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatStudentAnswer(dynamic answer) {
    if (answer == null) {
      return 'لم تتم الإجابة';
    }

    if (answer is bool) {
      return answer ? 'صح' : 'خطأ';
    }

    if (answer is Iterable) {
      final values = answer.map((item) => item.toString()).toList();
      if (values.isEmpty) {
        return 'لم تتم الإجابة';
      }
      return values.asMap().entries.map((entry) {
        return '${entry.key + 1}. ${entry.value}';
      }).join('\n');
    }

    final text = answer.toString().trim();
    return text.isEmpty ? 'لم تتم الإجابة' : text;
  }

  String _formatScore(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

class _StudentQuestionResult {
  const _StudentQuestionResult({
    required this.order,
    required this.questionId,
    required this.type,
    required this.text,
    required this.studentAnswer,
    required this.earnedScore,
    required this.maxScore,
  });

  final int order;
  final String questionId;
  final String type;
  final String text;
  final dynamic studentAnswer;
  final double? earnedScore;
  final double maxScore;
}
