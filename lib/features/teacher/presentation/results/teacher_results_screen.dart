import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';
import '../questions/result_print_service.dart';

class TeacherResultsScreen extends StatefulWidget {
  final SessionManager sessionManager;

  const TeacherResultsScreen({
    super.key,
    required this.sessionManager,
  });

  @override
  State<TeacherResultsScreen> createState() => _TeacherResultsScreenState();
}

class _TeacherResultsScreenState extends State<TeacherResultsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  String? _errorMessage;
  List<_TeacherQuiz> _quizzes = [];

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final teacherId = widget.sessionManager.currentSession?.uid;

      if (teacherId == null) {
        throw Exception('لم يتم العثور على جلسة المعلم.');
      }

      final snapshot = await _firestore
          .collection('quizzes')
          .where('teacherId', isEqualTo: teacherId)
          .get();

      final quizzes = snapshot.docs.map((doc) {
        final data = doc.data();

        return _TeacherQuiz(
          id: doc.id,
          title: data['title']?.toString() ?? 'اختبار',
          createdAt: _readDateTime(data['createdAt']),
        );
      }).toList();

      quizzes.sort((a, b) {
        final aDate = a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bDate.compareTo(aDate);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _quizzes = quizzes;
        _loading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل الاختبارات: ${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<_ResultSummary> _loadQuizSummary(
    String quizId,
  ) async {
    final teacherId = widget.sessionManager.currentSession?.uid;

    if (teacherId == null) {
      throw Exception('لم يتم العثور على جلسة المعلم.');
    }

    // The result document is created lazily in some flows (for example when
    // the teacher first opens the quiz results). The teacher dashboard must
    // still show a submitted attempt immediately, so count submitted attempts
    // as the source of truth and use results only for publication status.
    final attemptsSnapshot = await _firestore
        .collection('attempts')
        .where('quizId', isEqualTo: quizId)
        .where('status', isEqualTo: 'submitted')
        .get();

    final resultsSnapshot = await _firestore
        .collection('results')
        .where('teacherId', isEqualTo: teacherId)
        .where('quizId', isEqualTo: quizId)
        .get();

    final resultByAttemptId = <String, String>{};
    for (final doc in resultsSnapshot.docs) {
      final data = doc.data();
      final attemptId = data['attemptId']?.toString() ?? doc.id;
      if (attemptId.isNotEmpty) {
        resultByAttemptId[attemptId] =
            data['status']?.toString() ?? 'pending';
      }
    }

    var published = 0;
    var pending = 0;

    for (final attemptDoc in attemptsSnapshot.docs) {
      final status = resultByAttemptId[attemptDoc.id];

      if (status == 'published') {
        published++;
      } else {
        pending++;
      }
    }

    return _ResultSummary(
      total: attemptsSnapshot.docs.length,
      published: published,
      pending: pending,
    );
  }

  void _openQuizResults(_TeacherQuiz quiz) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherQuizResultsScreen(
          sessionManager: widget.sessionManager,
          quizId: quiz.id,
          quizTitle: quiz.title,
        ),
      ),
    );
  }

  Widget _buildQuizCard(_TeacherQuiz quiz) {
    return FutureBuilder<_ResultSummary>(
      future: _loadQuizSummary(quiz.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(
                quiz.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(
                quiz.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text(
                'تعذر تحميل ملخص النتائج.',
              ),
              trailing: IconButton(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh),
              ),
            ),
          );
        }

        final summary =
            snapshot.data ?? const _ResultSummary.empty();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openQuizResults(quiz),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    child: const Icon(
                      Icons.assessment_outlined,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          quiz.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            Text('النتائج: ${summary.total}'),
                            Text('منشورة: ${summary.published}'),
                            Text('قيد المراجعة: ${summary.pending}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_left),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadQuizzes,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_quizzes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadQuizzes,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(Icons.assessment_outlined, size: 64),
            SizedBox(height: 16),
            Center(
              child: Text(
                'لا توجد اختبارات للمعلم حتى الآن.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadQuizzes,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _quizzes.length,
        itemBuilder: (context, index) {
          return _buildQuizCard(_quizzes[index]);
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
          title: const Text(
            'نتائج الاختبارات',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _buildBody(),
        ),
      ),
    );
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }
}

class TeacherQuizResultsScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final String quizId;
  final String quizTitle;

  const TeacherQuizResultsScreen({
    super.key,
    required this.sessionManager,
    required this.quizId,
    required this.quizTitle,
  });

  @override
  State<TeacherQuizResultsScreen> createState() =>
      _TeacherQuizResultsScreenState();
}

class _TeacherQuizResultsScreenState
    extends State<TeacherQuizResultsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  String? _errorMessage;
  List<StudentResult> _results = [];

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final teacherId = widget.sessionManager.currentSession?.uid;

      if (teacherId == null) {
        throw Exception('لم يتم العثور على جلسة المعلم.');
      }

      final quizDoc = await _firestore
          .collection('quizzes')
          .doc(widget.quizId)
          .get();

      if (!quizDoc.exists) {
        throw Exception('لم يتم العثور على الاختبار.');
      }

      final quizData = quizDoc.data();

      if (quizData == null ||
          quizData['teacherId']?.toString() != teacherId) {
        throw Exception('لا تملك صلاحية عرض نتائج هذا الاختبار.');
      }

      await _autoGradeSubmittedAttempts(
        teacherId: teacherId,
      );

      final resultsSnapshot = await _firestore
          .collection('results')
          .where('teacherId', isEqualTo: teacherId)
          .where('quizId', isEqualTo: widget.quizId)
          .get();

      final results = <StudentResult>[];

      for (final doc in resultsSnapshot.docs) {
        final data = doc.data();

        results.add(
          StudentResult(
            id: doc.id,
            attemptId:
                data['attemptId']?.toString() ?? '',
            quizId:
                data['quizId']?.toString() ?? widget.quizId,
            studentId:
                data['studentId']?.toString() ?? '',
            autoScore:
                _readDouble(data['autoScore']) ?? 0,
            manualScore:
                _readDouble(data['manualScore']) ?? 0,
            totalScore:
                _readDouble(data['totalScore']) ?? 0,
            maxScore:
                _readDouble(data['maxScore']) ?? 0,
            status:
                data['status']?.toString() ?? 'pending',
            publishedAt:
                _readDateTime(data['publishedAt']),
          ),
        );
      }

      for (final result in results) {
        if (result.studentId.isEmpty) {
          continue;
        }

        final studentDoc = await _firestore
            .collection('students')
            .doc(result.studentId)
            .get();

        final studentData = studentDoc.data();

        result.studentName =
            studentData?['name']?.toString() ??
                'طالب غير معروف';
      }

      results.sort(
        (a, b) => a.studentName.compareTo(b.studentName),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _results = results;
        _loading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل النتائج: ${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _autoGradeSubmittedAttempts({
    required String teacherId,
  }) async {
    final existingResultsSnapshot = await _firestore
        .collection('results')
        .where('teacherId', isEqualTo: teacherId)
        .where('quizId', isEqualTo: widget.quizId)
        .get();

    final existingResultsByAttemptId = <String, Map<String, dynamic>>{};

    for (final resultDoc in existingResultsSnapshot.docs) {
      final data = resultDoc.data();
      final attemptId = data['attemptId']?.toString() ?? resultDoc.id;

      if (attemptId.isNotEmpty) {
        existingResultsByAttemptId[attemptId] = {
          ...data,
          '_resultId': resultDoc.id,
        };
      }
    }

    final attemptsSnapshot = await _firestore
        .collection('attempts')
        .where('quizId', isEqualTo: widget.quizId)
        .where('status', isEqualTo: 'submitted')
        .get();

    for (final attemptDoc in attemptsSnapshot.docs) {
      final existingResult = existingResultsByAttemptId[attemptDoc.id];
      final attemptData = attemptDoc.data();
      final studentId = attemptData['studentId']?.toString() ?? '';

      if (studentId.isEmpty) {
        continue;
      }

      if (existingResult != null) {
        final existingQuestionScores = existingResult['questionScores'];

        if (existingQuestionScores is Map &&
            existingQuestionScores.isNotEmpty) {
          // النتيجة موجودة بالفعل بدرجات الأسئلة؛ لا نعيد حسابها.
          // لكن نضيف مفتاح الإجابات الآمنة إذا كانت النتيجة قديمة.
          // Always backfill missing correct answers. Older results may have
          // a partial/empty correctAnswers map from before this feature.
          await _backfillQuestionScores(
            attemptId: attemptDoc.id,
            studentId: studentId,
            resultData: existingResult,
          );
          continue;
        }

        // النتيجة القديمة موجودة، لذلك نضيف questionScores فقط
        // مع الحفاظ على manualScores والدرجات الحالية.
        await _backfillQuestionScores(
          attemptId: attemptDoc.id,
          studentId: studentId,
          resultData: existingResult,
        );

        continue;
      }

      final result = await _calculateResult(
        attemptId: attemptDoc.id,
        studentId: studentId,
        teacherId: teacherId,
      );

      await _firestore
          .collection('results')
          .doc(attemptDoc.id)
          .set(result);
    }
  }

  Future<void> _backfillQuestionScores({
    required String attemptId,
    required String studentId,
    required Map<String, dynamic> resultData,
  }) async {
    final quizQuestionsSnapshot = await _firestore
        .collection('quizQuestions')
        .where('quizId', isEqualTo: widget.quizId)
        .get();

    final links = quizQuestionsSnapshot.docs
        .map((doc) {
          final data = doc.data();

          return _QuestionLink(
            questionId: data['questionId']?.toString() ?? '',
            order: _readInt(data['order']) ?? 0,
          );
        })
        .where((item) => item.questionId.isNotEmpty)
        .toList();

    links.sort((a, b) => a.order.compareTo(b.order));

    final answersSnapshot = await _firestore
        .collection('answers')
        .where('attemptId', isEqualTo: attemptId)
        .where('studentId', isEqualTo: studentId)
        .get();

    final answersByQuestion = <String, dynamic>{};

    for (final doc in answersSnapshot.docs) {
      final data = doc.data();
      final questionId = data['questionId']?.toString() ?? '';

      if (questionId.isNotEmpty) {
        answersByQuestion[questionId] = data['answer'];
      }
    }

    final questionScores = <String, dynamic>{};
    final correctAnswers = resultData['correctAnswers'] is Map
        ? Map<String, dynamic>.from(
            resultData['correctAnswers'] as Map,
          )
        : <String, dynamic>{};
    final existingQuestionScores = resultData['questionScores'];

    if (existingQuestionScores is Map) {
      for (final entry in existingQuestionScores.entries) {
        questionScores[entry.key.toString()] = entry.value;
      }
    }

    final manualScores = resultData['manualScores'] is Map
        ? Map<String, dynamic>.from(
            resultData['manualScores'] as Map,
          )
        : <String, dynamic>{};

    for (final link in links) {
      final hasExistingScore = questionScores.containsKey(link.questionId);

      final questionDoc = await _firestore
          .collection('questions')
          .doc(link.questionId)
          .get();

      if (!questionDoc.exists) {
        continue;
      }

      final questionData = questionDoc.data();
      if (questionData == null) {
        continue;
      }

      final type = questionData['type']?.toString() ?? '';
      final score = _readDouble(questionData['score']) ?? 0;
      final studentAnswer = answersByQuestion[link.questionId];

      // الأسئلة اليدوية لا نعيد حسابها هنا؛ نستخدم الدرجة المحفوظة.
      if (type == 'essay' || type == 'ordering') {
        if (!hasExistingScore &&
            manualScores.containsKey(link.questionId)) {
          questionScores[link.questionId] =
              manualScores[link.questionId];
        }
        final keyDoc = await _firestore
            .collection('questionKeys')
            .doc(link.questionId)
            .get();
        final keyData = keyDoc.data();
        if (keyData != null) {
          correctAnswers[link.questionId] =
              _displayCorrectAnswer(type, keyData, questionData);
        }
        continue;
      }

      final keyDoc = await _firestore
          .collection('questionKeys')
          .doc(link.questionId)
          .get();

      final keyData = keyDoc.data();
      if (keyData == null) {
        continue;
      }

      correctAnswers[link.questionId] =
          _displayCorrectAnswer(type, keyData, questionData);

      if (type == 'single_choice') {
        final correct = _readInt(keyData['correctOption']);
        final answerIndex = _answerIndex(
          studentAnswer,
          questionData['options'],
        );

        // Always recalculate automatically graded questions. Older results
        // may contain an incorrect cached score (for example 0/1 even when
        // the student answered صح and the correctOption is 0).
        questionScores[link.questionId] =
            correct != null &&
                    answerIndex != null &&
                    correct == answerIndex
                ? score
                : 0.0;
        continue;
      }

      if (_isTrueFalseType(type)) {
        final correct = _trueFalseAnswerIndex(keyData['correctOption']);
        final answerIndex = _trueFalseAnswerIndex(studentAnswer);

        // true_false answers are normalized to the option index: 0=صح,
        // 1=خطأ. This also repairs previously cached 0 scores.
        questionScores[link.questionId] =
            correct != null &&
                    answerIndex != null &&
                    correct == answerIndex
                ? score
                : 0.0;
        continue;
      }

      if (type == 'multiple_choice') {
        final correct = _readIntList(keyData['correctOptions']);
        final answer = _answerIndexList(
          studentAnswer,
          questionData['options'],
        );

        questionScores[link.questionId] =
            _sameIntSet(correct, answer) ? score : 0.0;
      }
    }

    if (questionScores.isEmpty && correctAnswers.isEmpty) {
      return;
    }

    final resultId = resultData['_resultId']?.toString();
    if (resultId == null || resultId.isEmpty) {
      return;
    }

    // Rebuild the automatic total from the refreshed per-question scores.
    // Keep manually graded scores untouched.
    double autoScore = 0.0;
    for (final link in links) {
      final questionDoc = await _firestore
          .collection('questions')
          .doc(link.questionId)
          .get();
      final data = questionDoc.data();
      if (data == null) continue;
      final type = data['type']?.toString() ?? '';
      if (type == 'essay' || type == 'ordering') continue;
      autoScore += _readDouble(questionScores[link.questionId]) ?? 0.0;
    }

    final manualScore = _readDouble(resultData['manualScore']) ?? 0.0;
    final totalScore = autoScore + manualScore;

    await _firestore
        .collection('results')
        .doc(resultId)
        .update({
      'questionScores': questionScores,
      'correctAnswers': correctAnswers,
      'autoScore': autoScore,
      'totalScore': totalScore,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<Map<String, dynamic>> _calculateResult({
    required String attemptId,
    required String studentId,
    required String teacherId,
  }) async {
    final quizQuestionsSnapshot = await _firestore
        .collection('quizQuestions')
        .where('quizId', isEqualTo: widget.quizId)
        .get();

    final links = quizQuestionsSnapshot.docs.map((doc) {
      final data = doc.data();

      return _QuestionLink(
        questionId:
            data['questionId']?.toString() ?? '',
        order: _readInt(data['order']) ?? 0,
      );
    }).where((item) => item.questionId.isNotEmpty).toList();

    links.sort((a, b) => a.order.compareTo(b.order));

    if (links.isEmpty) {
      throw Exception('لا توجد أسئلة مرتبطة بهذا الاختبار.');
    }

    final answersSnapshot = await _firestore
        .collection('answers')
        .where('attemptId', isEqualTo: attemptId)
        .where('studentId', isEqualTo: studentId)
        .get();

    final answersByQuestion = <String, dynamic>{};

    for (final doc in answersSnapshot.docs) {
      final data = doc.data();
      final questionId =
          data['questionId']?.toString();

      if (questionId == null || questionId.isEmpty) {
        continue;
      }

      answersByQuestion[questionId] = data['answer'];
    }

    double autoScore = 0;
    double maxScore = 0;
    var hasManualQuestions = false;

    // درجات كل سؤال بشكل آمن للعرض للطالب لاحقًا.
    // لا تحتوي على الإجابات الصحيحة أو questionKeys.
    final questionScores = <String, double>{};
    final correctAnswers = <String, dynamic>{};

    for (final link in links) {
      final questionDoc = await _firestore
          .collection('questions')
          .doc(link.questionId)
          .get();

      if (!questionDoc.exists) {
        continue;
      }

      final questionData = questionDoc.data();

      if (questionData == null) {
        continue;
      }

      final score =
          _readDouble(questionData['score']) ?? 0;

      maxScore += score;

      final type =
          questionData['type']?.toString() ?? '';

      final studentAnswer =
          answersByQuestion[link.questionId];

      final keyDoc = await _firestore
          .collection('questionKeys')
          .doc(link.questionId)
          .get();

      final keyData = keyDoc.data();

      if (keyData != null) {
        correctAnswers[link.questionId] =
            _displayCorrectAnswer(type, keyData, questionData);
      }

      if (type == 'single_choice') {
        if (keyData == null) {
          hasManualQuestions = true;
          continue;
        }

        final correct =
            _readInt(keyData['correctOption']);

        final answerIndex = _answerIndex(
          studentAnswer,
          questionData['options'],
        );

        final earned = correct != null &&
                answerIndex != null &&
                correct == answerIndex
            ? score
            : 0.0;

        questionScores[link.questionId] = earned;
        autoScore += earned;

        continue;
      }

      if (_isTrueFalseType(type)) {
        if (keyData == null) {
          hasManualQuestions = true;
          continue;
        }

        final correct = _trueFalseAnswerIndex(
          keyData['correctOption'],
        );

        final answerIndex = _trueFalseAnswerIndex(
          studentAnswer,
        );

        final earned = correct != null &&
                answerIndex != null &&
                correct == answerIndex
            ? score
            : 0.0;

        questionScores[link.questionId] = earned;
        autoScore += earned;

        continue;
      }

      if (type == 'multiple_choice') {
        if (keyData == null) {
          hasManualQuestions = true;
          continue;
        }

        final correct =
            _readIntList(keyData['correctOptions']);
        final answer = _answerIndexList(
          studentAnswer,
          questionData['options'],
        );

        final earned = _sameIntSet(correct, answer)
            ? score
            : 0.0;

        questionScores[link.questionId] = earned;
        autoScore += earned;

        continue;
      }

      hasManualQuestions = true;
      questionScores[link.questionId] = 0.0;
    }

    final now = Timestamp.now();

    return {
      'attemptId': attemptId,
      'quizId': widget.quizId,
      'studentId': studentId,
      'teacherId': teacherId,
      'autoScore': autoScore,
      'manualScore': 0,
      'totalScore': autoScore,
      'maxScore': maxScore,
      'questionScores': questionScores,
      'correctAnswers': correctAnswers,
      'status':
          hasManualQuestions ? 'pending' : 'published',
      'publishedAt':
          hasManualQuestions ? null : now,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  String _displayCorrectAnswer(
    String type,
    Map<String, dynamic> keyData,
    Map<String, dynamic> questionData,
  ) {
    final options = _readStringList(questionData['options']);

    if (type == 'single_choice' || _isTrueFalseType(type)) {
      final index = _trueFalseAnswerIndex(keyData['correctOption']);
      if (_isTrueFalseType(type)) {
        if (index == 0) return 'صح';
        if (index == 1) return 'خطأ';
      }
      if (index != null && index >= 0 && index < options.length) {
        return options[index];
      }
    }

    if (type == 'multiple_choice') {
      final indexes = _readIntList(keyData['correctOptions']);
      final values = indexes
          .where((index) => index >= 0 && index < options.length)
          .map((index) => options[index])
          .toList();
      return values.join('\n');
    }

    if (type == 'ordering') {
      final order = _readIntList(keyData['correctOrder']);
      if (order.isNotEmpty) {
        final values = order
            .where((index) => index >= 0 && index < options.length)
            .map((index) => options[index])
            .toList();
        if (values.isNotEmpty) {
          return values.join(' ← ');
        }
      }

      final model = keyData['modelAnswer'] ?? questionData['modelAnswer'];
      if (model is Iterable) {
        return model
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .join(' ← ');
      }
      return model?.toString() ?? 'غير متاحة';
    }

    return keyData['modelAnswer']?.toString() ??
        questionData['modelAnswer']?.toString() ??
        'تصحيح يدوي';
  }

  Widget _buildResultCard(StudentResult result) {
    final percentage = result.maxScore > 0
        ? (result.totalScore / result.maxScore) * 100
        : 0;

    final statusLabel =
        result.status == 'published'
            ? 'منشورة'
            : 'قيد المراجعة';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TeacherStudentResultScreen(
                sessionManager: widget.sessionManager,
                result: result,
                quizId: widget.quizId,
                quizTitle: widget.quizTitle,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                child: Text(
                  result.studentName.isEmpty
                      ? '?'
                      : result.studentName.characters.first,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.studentName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${result.totalScore} / ${result.maxScore}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'النسبة: ${percentage.toStringAsFixed(1)}%',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'التصحيح التلقائي: ${result.autoScore}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'التصحيح اليدوي: ${result.manualScore}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: result.status == 'published'
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                            : Theme.of(context)
                                .colorScheme
                                .tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadResults,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadResults,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(Icons.people_outline, size: 64),
            SizedBox(height: 16),
            Center(
              child: Text(
                'لا توجد نتائج مسلّمة لهذا الاختبار حتى الآن.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadResults,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          return _buildResultCard(_results[index]);
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
          title: Text(
            widget.quizTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _buildBody(),
        ),
      ),
    );
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }

  static double? _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  static List<int> _readIntList(dynamic value) {
    if (value is Iterable) {
      return value
          .map(_readInt)
          .whereType<int>()
          .toList();
    }

    final single = _readInt(value);
    return single == null ? [] : [single];
  }

  static List<String> _readStringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item?.toString() ?? '')
          .toList();
    }

    return [];
  }

  static int? _answerIndex(
    dynamic answer,
    dynamic optionsValue,
  ) {
    final options = _readStringList(optionsValue);

    if (answer is num) {
      final index = answer.toInt();
      if (index >= 0 && index < options.length) {
        return index;
      }
    }

    if (answer is String) {
      final directIndex = int.tryParse(answer);
      if (directIndex != null &&
          directIndex >= 0 &&
          directIndex < options.length) {
        return directIndex;
      }

      final answerText = answer.trim();
      final index = options.indexWhere(
        (option) => option.trim() == answerText,
      );

      if (index >= 0) {
        return index;
      }
    }

    return null;
  }

  static bool _isTrueFalseType(String type) {
    final value = type.trim().toLowerCase().replaceAll(' ', '');
    return value == 'true_false' ||
        value == 'true/false' ||
        value == 'truefalse' ||
        value == 'صح/خطأ' ||
        value == 'صح/خطا' ||
        value == 'صحخطأ' ||
        value == 'صحخطا';
  }

  static int? _trueFalseAnswerIndex(dynamic answer) {
    if (answer is bool) return answer ? 0 : 1;

    if (answer is num) {
      final index = answer.toInt();
      if (index == 0 || index == 1) return index;
    }

    if (answer is String) {
      final value = answer.trim().toLowerCase().replaceAll(' ', '');
      if (value == '0' || value == 'true' || value == 'صح') return 0;
      if (value == '1' || value == 'false' || value == 'خطأ' || value == 'خطا') return 1;
    }

    return null;
  }

  static List<int> _answerIndexList(
    dynamic answer,
    dynamic optionsValue,
  ) {
    if (answer is! Iterable) {
      final singleIndex = _answerIndex(answer, optionsValue);
      return singleIndex == null ? [] : [singleIndex];
    }

    return answer
        .map(
          (item) => _answerIndex(item, optionsValue),
        )
        .whereType<int>()
        .toList();
  }

  static bool _sameIntSet(
    List<int> first,
    List<int> second,
  ) {
    final a = first.toSet();
    final b = second.toSet();

    return a.length == b.length && a.containsAll(b);
  }
}

class TeacherStudentResultScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final StudentResult result;
  final String quizId;
  final String quizTitle;

  const TeacherStudentResultScreen({
    super.key,
    required this.sessionManager,
    required this.result,
    required this.quizId,
    required this.quizTitle,
  });

  @override
  State<TeacherStudentResultScreen> createState() =>
      _TeacherStudentResultScreenState();
}

class _TeacherStudentResultScreenState
    extends State<TeacherStudentResultScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  List<_ManualQuestion> _manualQuestions = [];
  final Map<String, TextEditingController> _scoreControllers = {};

  @override
  void initState() {
    super.initState();
    _loadAnswers();
  }

  @override
  void dispose() {
    for (final controller in _scoreControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAnswers() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final teacherId = widget.sessionManager.currentSession?.uid;
      if (teacherId == null) {
        throw Exception('لم يتم العثور على جلسة المعلم.');
      }

      if (widget.result.studentId.isEmpty ||
          widget.result.attemptId.isEmpty) {
        throw Exception('بيانات نتيجة الطالب غير مكتملة.');
      }

      final quizDoc = await _firestore
          .collection('quizzes')
          .doc(widget.quizId)
          .get();

      final quizData = quizDoc.data();
      if (!quizDoc.exists ||
          quizData == null ||
          quizData['teacherId']?.toString() != teacherId) {
        throw Exception('لا تملك صلاحية عرض هذه النتيجة.');
      }

      final resultDoc = await _firestore
          .collection('results')
          .doc(widget.result.id)
          .get();
      final resultData = resultDoc.data() ?? <String, dynamic>{};
      final savedManualScores = resultData['manualScores'] is Map
          ? Map<String, dynamic>.from(resultData['manualScores'] as Map)
          : <String, dynamic>{};

      final linksSnapshot = await _firestore
          .collection('quizQuestions')
          .where('quizId', isEqualTo: widget.quizId)
          .get();

      final links = linksSnapshot.docs.map((doc) {
        final data = doc.data();
        return _QuestionLink(
          questionId: data['questionId']?.toString() ?? '',
          order: _readInt(data['order']) ?? 0,
        );
      }).where((item) => item.questionId.isNotEmpty).toList();

      links.sort((a, b) => a.order.compareTo(b.order));

      final answersSnapshot = await _firestore
          .collection('answers')
          .where('attemptId', isEqualTo: widget.result.attemptId)
          .where('studentId', isEqualTo: widget.result.studentId)
          .get();

      final answersByQuestion = <String, dynamic>{};
      for (final doc in answersSnapshot.docs) {
        final data = doc.data();
        final questionId = data['questionId']?.toString() ?? '';
        if (questionId.isNotEmpty) {
          answersByQuestion[questionId] = data['answer'];
        }
      }

      final manualQuestions = <_ManualQuestion>[];

      for (final link in links) {
        final questionDoc = await _firestore
            .collection('questions')
            .doc(link.questionId)
            .get();

        final questionData = questionDoc.data();
        if (!questionDoc.exists || questionData == null) {
          continue;
        }

        final type = questionData['type']?.toString() ?? '';
        if (type != 'essay' && type != 'ordering') {
          continue;
        }

        final score = _readDouble(questionData['score']) ?? 0;
        final keyDoc = await _firestore
            .collection('questionKeys')
            .doc(link.questionId)
            .get();
        final keyData = keyDoc.data() ?? <String, dynamic>{};

        final existingManualScore = _readDouble(
          savedManualScores[link.questionId],
        );

        final controller = TextEditingController(
          text: existingManualScore?.toString() ?? '',
        );
        _scoreControllers[link.questionId] = controller;

        manualQuestions.add(
          _ManualQuestion(
            questionId: link.questionId,
            order: link.order,
            type: type,
            text: questionData['text']?.toString() ?? '',
            maxScore: score,
            studentAnswer: answersByQuestion[link.questionId],
            modelAnswer: keyData['modelAnswer'],
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _manualQuestions = manualQuestions;
        _loading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل إجابات الطالب: ${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _printStudentResult() async {
    if (_loading || _saving) return;

    try {
      final teacherId = widget.sessionManager.currentSession?.uid;
      if (teacherId == null) throw Exception('لم يتم العثور على جلسة المعلم.');

      final quizDoc = await _firestore.collection('quizzes').doc(widget.quizId).get();
      final quizData = quizDoc.data();
      if (!quizDoc.exists || quizData == null || quizData['teacherId']?.toString() != teacherId) {
        throw Exception('لا تملك صلاحية طباعة هذه النتيجة.');
      }

      final resultDoc = await _firestore.collection('results').doc(widget.result.id).get();
      final resultData = resultDoc.data() ?? <String, dynamic>{};
      final questionScores = resultData['questionScores'] is Map
          ? Map<String, dynamic>.from(resultData['questionScores'] as Map)
          : <String, dynamic>{};
      final manualScores = resultData['manualScores'] is Map
          ? Map<String, dynamic>.from(resultData['manualScores'] as Map)
          : <String, dynamic>{};

      final linksSnapshot = await _firestore.collection('quizQuestions').where('quizId', isEqualTo: widget.quizId).get();
      final links = linksSnapshot.docs.map((doc) {
        final data = doc.data();
        return _QuestionLink(questionId: data['questionId']?.toString() ?? '', order: _readInt(data['order']) ?? 0);
      }).where((item) => item.questionId.isNotEmpty).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      final answersSnapshot = await _firestore.collection('answers')
          .where('attemptId', isEqualTo: widget.result.attemptId)
          .where('studentId', isEqualTo: widget.result.studentId)
          .get();
      final answersByQuestion = <String, dynamic>{};
      for (final doc in answersSnapshot.docs) {
        final data = doc.data();
        final id = data['questionId']?.toString() ?? '';
        if (id.isNotEmpty) answersByQuestion[id] = data['answer'];
      }

      final questions = <ResultPrintQuestion>[];
      for (final link in links) {
        final questionDoc = await _firestore.collection('questions').doc(link.questionId).get();
        final questionData = questionDoc.data();
        if (!questionDoc.exists || questionData == null) continue;

        final type = questionData['type']?.toString() ?? '';
        final options = _readStringList(questionData['options']);
        final studentAnswer = answersByQuestion[link.questionId];
        final keyDoc = await _firestore.collection('questionKeys').doc(link.questionId).get();
        final keyData = keyDoc.data();
        final score = _readDouble(questionData['score']) ?? 0;
        final earned = _readDouble(questionScores[link.questionId]) ??
            _readDouble(manualScores[link.questionId]) ?? 0;

        questions.add(ResultPrintQuestion(
          number: link.order,
          text: questionData['text']?.toString() ?? '',
          type: type,
          studentAnswer: _formatStudentAnswer(type, studentAnswer, options),
          correctAnswer: _formatCorrectAnswer(type, keyData, options, questionData),
          score: score,
          earnedScore: earned,
        ));
      }

      if (questions.isEmpty) throw Exception('لا توجد أسئلة متاحة للطباعة.');

      await printStudentResult(
        quizTitle: widget.quizTitle,
        studentName: widget.result.studentName,
        totalScore: widget.result.totalScore,
        maxScore: widget.result.maxScore,
        autoScore: widget.result.autoScore,
        manualScore: widget.result.manualScore,
        status: widget.result.status,
        questions: questions,
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('تعذر طباعة نتيجة الطالب:\n${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  static String _formatStudentAnswer(String type, dynamic answer, List<String> options) {
    if (answer == null) return 'لم يجب الطالب';
    if (_isTrueFalseType(type)) {
      final index = _trueFalseAnswerIndex(answer);
      if (index == 0) return 'صح';
      if (index == 1) return 'خطأ';
    }
    if (answer is Iterable) {
      final values = answer.map((item) {
        final index = _answerIndex(item, options);
        return index != null && index >= 0 && index < options.length ? options[index] : item?.toString() ?? '';
      }).where((v) => v.isNotEmpty).toList();
      return values.isEmpty ? 'لم يجب الطالب' : values.join(' ، ');
    }
    final index = _answerIndex(answer, options);
    if (index != null && index >= 0 && index < options.length) return options[index];
    final value = answer.toString().trim();
    return value.isEmpty ? 'لم يجب الطالب' : value;
  }

  static String _formatCorrectAnswer(String type, Map<String, dynamic>? keyData, List<String> options, Map<String, dynamic> questionData) {
    if (keyData == null) return type == 'essay' ? (questionData['modelAnswer']?.toString() ?? 'تصحيح يدوي') : 'غير متاحة';
    if (type == 'single_choice') {
      final index = _readInt(keyData['correctOption']);
      return index != null && index >= 0 && index < options.length ? options[index] : 'غير متاحة';
    }
    if (type == 'multiple_choice') {
      final indexes = _readIntList(keyData['correctOptions']);
      final values = indexes.where((i) => i >= 0 && i < options.length).map((i) => options[i]).toList();
      return values.isEmpty ? 'غير متاحة' : values.join(' ، ');
    }
    if (_isTrueFalseType(type)) {
      final index = _readInt(keyData['correctOption']);
      if (index == 0) return 'صح';
      if (index == 1) return 'خطأ';
      return 'غير متاحة';
    }
    if (type == 'essay') return keyData['modelAnswer']?.toString() ?? questionData['modelAnswer']?.toString() ?? 'تصحيح يدوي';
    if (type == 'ordering') {
      final model = keyData['modelAnswer'] ?? questionData['modelAnswer'];
      if (model is Iterable) return model.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).join(' ← ');
      return model?.toString() ?? 'تصحيح يدوي';
    }
    return keyData['modelAnswer']?.toString() ?? 'غير متاحة';
  }

  String _displayCorrectAnswer(
    String type,
    Map<String, dynamic> keyData,
    Map<String, dynamic> questionData,
  ) {
    final options = _readStringList(questionData['options']);

    if (type == 'single_choice' || _isTrueFalseType(type)) {
      final index = _trueFalseAnswerIndex(keyData['correctOption']);
      if (_isTrueFalseType(type)) {
        if (index == 0) return 'صح';
        if (index == 1) return 'خطأ';
      }
      if (index != null && index >= 0 && index < options.length) {
        return options[index];
      }
    }

    if (type == 'multiple_choice') {
      final indexes = _readIntList(keyData['correctOptions']);
      return indexes
          .where((index) => index >= 0 && index < options.length)
          .map((index) => options[index])
          .join('\n');
    }

    if (type == 'ordering') {
      final order = _readIntList(keyData['correctOrder']);
      if (order.isNotEmpty) {
        final values = order
            .where((index) => index >= 0 && index < options.length)
            .map((index) => options[index])
            .toList();
        if (values.isNotEmpty) {
          return values.join(' ← ');
        }
      }

      final model = keyData['modelAnswer'] ?? questionData['modelAnswer'];
      if (model is Iterable) {
        return model
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .join(' ← ');
      }
      return model?.toString() ?? 'غير متاحة';
    }

    return keyData['modelAnswer']?.toString() ??
        questionData['modelAnswer']?.toString() ??
        'تصحيح يدوي';
  }

  Future<void> _republishResult() async {
    if (_saving) return;

    if (mounted) setState(() => _saving = true);

    try {
      final teacherId = widget.sessionManager.currentSession?.uid;
      if (teacherId == null) {
        throw Exception('لم يتم العثور على جلسة المعلم.');
      }

      final resultRef = _firestore.collection('results').doc(widget.result.id);
      final resultSnapshot = await resultRef.get();
      final resultData = resultSnapshot.data();
      if (resultData == null) {
        throw Exception('النتيجة غير موجودة.');
      }

      final manualScores = resultData['manualScores'] is Map
          ? Map<String, dynamic>.from(resultData['manualScores'] as Map)
          : <String, dynamic>{};

      final linksSnapshot = await _firestore
          .collection('quizQuestions')
          .where('quizId', isEqualTo: widget.quizId)
          .get();

      var manualCount = 0;
      var gradedManualCount = 0;
      final correctAnswers = resultData['correctAnswers'] is Map
          ? Map<String, dynamic>.from(resultData['correctAnswers'] as Map)
          : <String, dynamic>{};

      for (final linkDoc in linksSnapshot.docs) {
        final linkData = linkDoc.data();
        final questionId = linkData['questionId']?.toString() ?? '';
        if (questionId.isEmpty) continue;

        final questionDoc = await _firestore
            .collection('questions')
            .doc(questionId)
            .get();
        final questionData = questionDoc.data();
        if (!questionDoc.exists || questionData == null) continue;

        final type = questionData['type']?.toString() ?? '';
        if (type == 'essay' || type == 'ordering') {
          manualCount++;
          if (manualScores.containsKey(questionId)) gradedManualCount++;
        }

        final keyDoc = await _firestore
            .collection('questionKeys')
            .doc(questionId)
            .get();
        final keyData = keyDoc.data();
        if (keyData != null) {
          correctAnswers[questionId] = _displayCorrectAnswer(
            type,
            keyData,
            questionData,
          );
        }
      }

      if (manualCount > 0 && gradedManualCount < manualCount) {
        throw Exception(
          'لا يمكن نشر النتيجة قبل تصحيح جميع الأسئلة اليدوية.',
        );
      }

      final questionScores = resultData['questionScores'] is Map
          ? Map<String, dynamic>.from(resultData['questionScores'] as Map)
          : <String, dynamic>{};

      final autoScore = _readDouble(resultData['autoScore']) ?? 0;
      final manualScore = manualScores.values.fold<double>(
        0,
        (total, value) => total + (_readDouble(value) ?? 0),
      );
      final totalScore = autoScore + manualScore;
      final now = Timestamp.now();

      await resultRef.update({
        'teacherId': teacherId,
        'autoScore': autoScore,
        'manualScore': manualScore,
        'totalScore': totalScore,
        'questionScores': questionScores,
        'manualScores': manualScores,
        'correctAnswers': correctAnswers,
        'status': 'published',
        'publishedAt': now,
        'updatedAt': now,
      });

      if (!mounted) return;
      _showMessage('تم تحديث ونشر النتيجة بنجاح.');
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      _showMessage('حدث خطأ أثناء تحديث النتيجة: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveManualGrading() async {
    if (_saving) return;

    final scores = <String, double>{};
    for (final question in _manualQuestions) {
      final raw = _scoreControllers[question.questionId]?.text.trim() ?? '';
      final score = double.tryParse(raw);

      if (score == null) {
        _showMessage(
          'أدخل درجة صحيحة للسؤال رقم ${question.order}.',
        );
        return;
      }

      if (score < 0 || score > question.maxScore) {
        _showMessage(
          'درجة السؤال رقم ${question.order} يجب أن تكون بين 0 و ${_formatNumber(question.maxScore)}.',
        );
        return;
      }

      scores[question.questionId] = score;
    }

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      final teacherId = widget.sessionManager.currentSession?.uid;
      if (teacherId == null) {
        throw Exception('لم يتم العثور على جلسة المعلم.');
      }

      final manualScore = scores.values.fold<double>(
        0,
        (total, value) => total + value,
      );
      final totalScore = widget.result.autoScore + manualScore;
      final allManualGraded = _manualQuestions.every(
        (question) => scores.containsKey(question.questionId),
      );

      final resultRef = _firestore
          .collection('results')
          .doc(widget.result.id);

      final resultSnapshot = await resultRef.get();
      final resultData = resultSnapshot.data() ?? <String, dynamic>{};
      final questionScores = resultData['questionScores'] is Map
          ? Map<String, dynamic>.from(
              resultData['questionScores'] as Map,
            )
          : <String, dynamic>{};

      for (final entry in scores.entries) {
        questionScores[entry.key] = entry.value;
      }

      final correctAnswers = resultData['correctAnswers'] is Map
          ? Map<String, dynamic>.from(
              resultData['correctAnswers'] as Map,
            )
          : <String, dynamic>{};

      // Older results may not have all display-safe correct answers copied
      // into the result document yet. Fill every missing question key; never
      // expose questionKeys to the student directly.
      {
        final linksSnapshot = await _firestore
            .collection('quizQuestions')
            .where('quizId', isEqualTo: widget.quizId)
            .get();

        for (final linkDoc in linksSnapshot.docs) {
          final linkData = linkDoc.data();
          final questionId = linkData['questionId']?.toString() ?? '';
          if (questionId.isEmpty) continue;

          final questionDoc = await _firestore
              .collection('questions')
              .doc(questionId)
              .get();
          final keyDoc = await _firestore
              .collection('questionKeys')
              .doc(questionId)
              .get();
          final questionData = questionDoc.data();
          final keyData = keyDoc.data();
          if (questionData == null || keyData == null) continue;

          if (!correctAnswers.containsKey(questionId) ||
              (correctAnswers[questionId]?.toString().trim().isEmpty ?? true)) {
            correctAnswers[questionId] = _displayCorrectAnswer(
              questionData['type']?.toString() ?? '',
              keyData,
              questionData,
            );
          }
        }
      }

      final now = Timestamp.now();

      await resultRef.update({
        'teacherId': teacherId,
        'manualScore': manualScore,
        'totalScore': totalScore,
        'maxScore': widget.result.maxScore,
        'questionScores': questionScores,
        'correctAnswers': correctAnswers,
        'manualScores': scores,
        'status': allManualGraded ? 'published' : 'pending',
        'publishedAt': allManualGraded ? now : null,
        'updatedAt': now,
      });

      if (!mounted) return;

      _showMessage('تم حفظ التصحيح اليدوي بنجاح.');
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      _showMessage(
        'حدث خطأ أثناء حفظ التصحيح: ${e.message ?? e.code}',
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildScoreCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildAnswer(_ManualQuestion question) {
    final answer = question.studentAnswer;

    if (answer == null ||
        (answer is String && answer.trim().isEmpty) ||
        (answer is Iterable && answer.isEmpty)) {
      return const Text('لم يكتب الطالب إجابة.');
    }

    if (answer is Iterable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: answer.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• ${item?.toString() ?? ''}'),
          );
        }).toList(),
      );
    }

    return Text(answer.toString());
  }

  Widget _buildManualQuestion(_ManualQuestion question) {
    final controller = _scoreControllers[question.questionId]!;
    final isEssay = question.type == 'essay';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'السؤال ${question.order}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              question.text,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 14),
            Text(
              'إجابة الطالب:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),
              child: _buildAnswer(question),
            ),
            if (isEssay && question.modelAnswer != null) ...[
              const SizedBox(height: 14),
              Text(
                'الإجابة النموذجية:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant,
                  ),
                ),
                child: Text(question.modelAnswer.toString()),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الدرجة القصوى: ${_formatNumber(question.maxScore)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'الدرجة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadAnswers,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final percentage = widget.result.maxScore > 0
        ? (widget.result.totalScore / widget.result.maxScore) * 100
        : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.person_outline, size: 60),
                const SizedBox(height: 12),
                Text(
                  widget.result.studentName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.quizTitle,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _loading || _saving ? null : _republishResult,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish_outlined),
            label: Text(
              _saving
                  ? 'جارٍ تحديث ونشر النتيجة...'
                  : (widget.result.status == 'published'
                      ? 'تحديث وإعادة نشر النتيجة'
                      : 'نشر النتيجة'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildScoreCard(
          context,
          'الدرجة النهائية الحالية',
          '${_formatNumber(widget.result.totalScore)} / ${_formatNumber(widget.result.maxScore)}',
          Icons.score_outlined,
        ),
        _buildScoreCard(
          context,
          'النسبة الحالية',
          '${percentage.toStringAsFixed(1)}%',
          Icons.percent_outlined,
        ),
        _buildScoreCard(
          context,
          'التصحيح التلقائي',
          _formatNumber(widget.result.autoScore),
          Icons.auto_fix_high_outlined,
        ),
        _buildScoreCard(
          context,
          'التصحيح اليدوي الحالي',
          _formatNumber(widget.result.manualScore),
          Icons.edit_outlined,
        ),
        const SizedBox(height: 8),
        if (_manualQuestions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'لا توجد أسئلة تحتاج إلى تصحيح يدوي في هذا الاختبار.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          const Text(
            'التصحيح اليدوي',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ..._manualQuestions.map(_buildManualQuestion),
          const SizedBox(height: 4),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveManualGrading,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _saving ? 'جارٍ الحفظ...' : 'حفظ التصحيح اليدوي',
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'تصحيح نتيجة الطالب',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: widget.result.status == 'published'
                  ? 'تحديث وإعادة نشر'
                  : 'نشر النتيجة',
              onPressed: _loading || _saving ? null : _republishResult,
              icon: const Icon(Icons.publish_outlined),
            ),
            IconButton(
              tooltip: 'طباعة نتيجة الطالب',
              onPressed: _loading || _saving ? null : _printStudentResult,
              icon: const Icon(Icons.print_outlined),
            ),
          ],
        ),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  static List<String> _readStringList(dynamic value) {
    if (value is Iterable) return value.map((e) => e?.toString() ?? '').toList();
    return [];
  }

  static bool _isTrueFalseType(String type) {
    final value = type.trim().toLowerCase().replaceAll(' ', '');
    return value == 'true_false' ||
        value == 'true/false' ||
        value == 'truefalse' ||
        value == 'صح/خطأ' ||
        value == 'صح/خطا' ||
        value == 'صحخطأ' ||
        value == 'صحخطا';
  }

  static int? _answerIndex(dynamic answer, List<String> options) {
    if (answer is num) {
      final index = answer.toInt();
      if (index >= 0 && index < options.length) return index;
    }
    if (answer is String) {
      final direct = int.tryParse(answer);
      if (direct != null && direct >= 0 && direct < options.length) return direct;
      final index = options.indexWhere((o) => o.trim() == answer.trim());
      if (index >= 0) return index;
    }
    return null;
  }

  static int? _trueFalseAnswerIndex(dynamic answer) {
    if (answer is bool) return answer ? 0 : 1;

    if (answer is num) {
      final index = answer.toInt();
      if (index == 0 || index == 1) return index;
    }

    if (answer is String) {
      final value = answer.trim().toLowerCase().replaceAll(' ', '');
      if (value == '0' || value == 'true' || value == 'صح') return 0;
      if (value == '1' || value == 'false' || value == 'خطأ' || value == 'خطا') return 1;
    }

    return null;
  }

  static List<int> _readIntList(dynamic value) {
    if (value is Iterable) return value.map(_readInt).whereType<int>().toList();
    final single = _readInt(value);
    return single == null ? [] : [single];
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _ManualQuestion {
  final String questionId;
  final int order;
  final String type;
  final String text;
  final double maxScore;
  final dynamic studentAnswer;
  final dynamic modelAnswer;

  const _ManualQuestion({
    required this.questionId,
    required this.order,
    required this.type,
    required this.text,
    required this.maxScore,
    required this.studentAnswer,
    required this.modelAnswer,
  });
}

class StudentResult {
  final String id;
  final String attemptId;
  final String quizId;
  final String studentId;
  final double autoScore;
  final double manualScore;
  final double totalScore;
  final double maxScore;
  final String status;
  final DateTime? publishedAt;
  String studentName;

  StudentResult({
    required this.id,
    required this.attemptId,
    required this.quizId,
    required this.studentId,
    required this.autoScore,
    required this.manualScore,
    required this.totalScore,
    required this.maxScore,
    required this.status,
    required this.publishedAt,
    this.studentName = 'طالب غير معروف',
  });
}

class _TeacherQuiz {
  final String id;
  final String title;
  final DateTime? createdAt;

  const _TeacherQuiz({
    required this.id,
    required this.title,
    required this.createdAt,
  });
}

class _ResultSummary {
  final int total;
  final int published;
  final int pending;

  const _ResultSummary({
    required this.total,
    required this.published,
    required this.pending,
  });

  const _ResultSummary.empty()
      : total = 0,
        published = 0,
        pending = 0;
}

class _QuestionLink {
  final String questionId;
  final int order;

  const _QuestionLink({
    required this.questionId,
    required this.order,
  });
}
