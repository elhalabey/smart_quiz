import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';

class StudentQuizzesScreen extends StatefulWidget {
  final SessionManager sessionManager;

  const StudentQuizzesScreen({
    super.key,
    required this.sessionManager,
  });

  @override
  State<StudentQuizzesScreen> createState() => _StudentQuizzesScreenState();
}

class _StudentQuizzesScreenState extends State<StudentQuizzesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  String? _errorMessage;
  List<_StudentQuiz> _quizzes = [];

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
      final studentId = widget.sessionManager.currentSession?.uid;

      if (studentId == null) {
        throw Exception('لم يتم العثور على جلسة الطالب.');
      }

      final studentDoc =
          await _firestore.collection('students').doc(studentId).get();

      if (!studentDoc.exists) {
        throw Exception('لم يتم العثور على بيانات الطالب.');
      }

      final studentData = studentDoc.data();

      if (studentData == null) {
        throw Exception('بيانات الطالب غير متاحة.');
      }

      final classId = studentData['classId']?.toString();

      if (classId == null || classId.isEmpty) {
        throw Exception('لم يتم تحديد فصل الطالب.');
      }

      final quizClassesSnapshot = await _firestore
          .collection('quizClasses')
          .where('classId', isEqualTo: classId)
          .get();

      final quizIds = quizClassesSnapshot.docs
          .map((doc) => doc.data()['quizId']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();

      // Load this student's attempts once so submitted quizzes are
      // displayed as submitted instead of appearing available.
      final attemptsSnapshot = await _firestore
          .collection('attempts')
          .where('studentId', isEqualTo: studentId)
          .get();

      final attemptStatusByQuizId = <String, String>{};
      for (final attemptDoc in attemptsSnapshot.docs) {
        final attemptData = attemptDoc.data();
        final attemptQuizId = attemptData['quizId']?.toString();
        final attemptStatus = attemptData['status']?.toString();

        if (attemptQuizId == null ||
            attemptQuizId.isEmpty ||
            attemptStatus == null ||
            attemptStatus.isEmpty) {
          continue;
        }

        // A submitted attempt takes priority over any older in-progress
        // attempt for the same quiz.
        if (attemptStatus == 'submitted' ||
            !attemptStatusByQuizId.containsKey(attemptQuizId)) {
          attemptStatusByQuizId[attemptQuizId] = attemptStatus;
        }
      }

      final quizzes = <_StudentQuiz>[];

      for (final quizId in quizIds) {
        DocumentSnapshot<Map<String, dynamic>> quizDoc;

        try {
          quizDoc =
              await _firestore.collection('quizzes').doc(quizId).get();
        } on FirebaseException catch (e) {
          // Students are only allowed to read published quizzes.
          // A draft/closed/archived quiz may still have a quizClasses
          // mapping, so permission-denied for that quiz must not prevent
          // the rest of the student's published quizzes from loading.
          if (e.code == 'permission-denied') {
            continue;
          }
          rethrow;
        }

        if (!quizDoc.exists) {
          continue;
        }

        final data = quizDoc.data();

        if (data == null || data['status']?.toString() != 'published') {
          continue;
        }

        final startAt = _readDateTime(data['startAt']);
        final endAt = _readDateTime(data['endAt']);
        final createdAt =
            _readDateTime(data['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);

        quizzes.add(
          _StudentQuiz(
            id: quizDoc.id,
            title: data['title']?.toString() ?? 'اختبار',
            description: data['description']?.toString() ?? '',
            subjectId: data['subjectId']?.toString() ?? '',
            startAt: startAt,
            endAt: endAt,
            createdAt: createdAt,
            attemptStatus: attemptStatusByQuizId[quizId],
          ),
        );
      }

      quizzes.sort((a, b) {
        final aDate = a.startAt ?? a.createdAt;
        final bDate = b.startAt ?? b.createdAt;
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

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return 'غير محدد';
    }

    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$day/$month/$year - $hour:$minute';
  }

  String _getQuizState(_StudentQuiz quiz) {
    if (quiz.attemptStatus == 'submitted') {
      return 'تم التسليم';
    }

    final now = DateTime.now();

    if (quiz.startAt != null && now.isBefore(quiz.startAt!)) {
      return 'لم يبدأ';
    }

    if (quiz.endAt != null && now.isAfter(quiz.endAt!)) {
      return 'انتهى';
    }

    return 'متاح';
  }

  Color _getStateColor(BuildContext context, String state) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (state) {
      case 'متاح':
        return colorScheme.primary;
      case 'لم يبدأ':
        return colorScheme.tertiary;
      case 'انتهى':
        return colorScheme.error;
      case 'تم التسليم':
        return colorScheme.outline;
      default:
        return colorScheme.outline;
    }
  }

  void _showQuizDetails(
    BuildContext context,
    _StudentQuiz quiz,
  ) {
    final state = _getQuizState(quiz);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final stateColor = _getStateColor(sheetContext, state);

        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    quiz.title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (quiz.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      quiz.description,
                      style: TextStyle(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    sheetContext,
                    Icons.info_outline,
                    'الحالة',
                    state,
                    valueColor: stateColor,
                  ),
                  const SizedBox(height: 10),
                  _buildDetailRow(
                    sheetContext,
                    Icons.play_circle_outline,
                    'بداية الاختبار',
                    _formatDateTime(quiz.startAt),
                  ),
                  const SizedBox(height: 10),
                  _buildDetailRow(
                    sheetContext,
                    Icons.event_available_outlined,
                    'نهاية الاختبار',
                    _formatDateTime(quiz.endAt),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: state == 'متاح'
                        ? () {
                            Navigator.of(sheetContext).pop();
                            _startQuiz(quiz);
                          }
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('بدء الاختبار'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startQuiz(_StudentQuiz quiz) async {
    final studentId = widget.sessionManager.currentSession?.uid;

    if (studentId == null) {
      return;
    }

    final quizState = _getQuizState(quiz);

    if (quizState == 'تم التسليم') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسليم هذا الاختبار بالفعل.'),
          ),
        );
      }
      return;
    }

    if (quizState != 'متاح') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الاختبار غير متاح حاليًا.'),
          ),
        );
      }
      return;
    }

    try {
      final existingAttemptSnapshot = await _firestore
          .collection('attempts')
          .where('quizId', isEqualTo: quiz.id)
          .where('studentId', isEqualTo: studentId)
          .get();

      for (final doc in existingAttemptSnapshot.docs) {
        final data = doc.data();
        final status = data['status']?.toString() ?? '';

        if (status == 'submitted') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم تسليم هذا الاختبار بالفعل.'),
              ),
            );
          }
          return;
        }

        if (status == 'in_progress') {
          if (!mounted) {
            return;
          }

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StudentQuizScreen(
                sessionManager: widget.sessionManager,
                attemptId: doc.id,
                quizId: quiz.id,
                quizTitle: quiz.title,
                quizEndAt: quiz.endAt,
              ),
            ),
          );
          return;
        }
      }

      final now = Timestamp.now();
      final attemptRef = _firestore.collection('attempts').doc();

      await attemptRef.set({
        'quizId': quiz.id,
        'studentId': studentId,
        'startedAt': now,
        'submittedAt': null,
        'status': 'in_progress',
        'createdAt': now,
      });

      if (!mounted) {
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StudentQuizScreen(
            sessionManager: widget.sessionManager,
            attemptId: attemptRef.id,
            quizId: quiz.id,
            quizTitle: quiz.title,
            quizEndAt: quiz.endAt,
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر بدء الاختبار: ${e.message ?? e.code}',
          ),
        ),
      );
    }
  }

  Widget _buildDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 21,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight:
                  valueColor != null ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuizCard(
    BuildContext context,
    _StudentQuiz quiz,
  ) {
    final state = _getQuizState(quiz);
    final stateColor = _getStateColor(context, state);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showQuizDetails(context, quiz),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                child: Icon(
                  state == 'متاح'
                      ? Icons.assignment_outlined
                      : Icons.assignment_late_outlined,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    if (quiz.description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        quiz.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_outlined,
                          size: 16,
                          color: stateColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          state,
                          style: TextStyle(
                            color: stateColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
  }

  Widget _buildBody(BuildContext context) {
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
            Icon(Icons.assignment_outlined, size: 64),
            SizedBox(height: 16),
            Center(
              child: Text(
                'لا توجد اختبارات متاحة حاليًا.',
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
          return _buildQuizCard(context, _quizzes[index]);
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
            'الاختبارات المتاحة',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _buildBody(context),
        ),
      ),
    );
  }
}

class StudentQuizScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final String attemptId;
  final String quizId;
  final String quizTitle;
  final DateTime? quizEndAt;

  const StudentQuizScreen({
    super.key,
    required this.sessionManager,
    required this.attemptId,
    required this.quizId,
    required this.quizTitle,
    required this.quizEndAt,
  });

  @override
  State<StudentQuizScreen> createState() => _StudentQuizScreenState();
}

class _StudentQuizScreenState extends State<StudentQuizScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;

  List<_StudentQuestion> _questions = [];
  int _currentIndex = 0;

  final Map<String, dynamic> _answers = {};
  final Map<String, DateTime> _questionStartedAt = {};

  Timer? _timer;
  DateTime? _quizEndAt;
  DateTime? _currentQuestionDeadline;
  Duration _remaining = Duration.zero;

  final Map<String, TextEditingController> _essayControllers = {};

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();

    for (final controller in _essayControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  Future<void> _loadQuestions() async {
    try {
      final attemptDoc = await _firestore
          .collection('attempts')
          .doc(widget.attemptId)
          .get();

      if (!attemptDoc.exists) {
        throw Exception('لم يتم العثور على محاولة الاختبار.');
      }

      final attemptData = attemptDoc.data();

      if (attemptData == null) {
        throw Exception('بيانات محاولة الاختبار غير متاحة.');
      }

      final studentId = widget.sessionManager.currentSession?.uid;

      if (studentId == null ||
          attemptData['studentId']?.toString() != studentId) {
        throw Exception('لا يمكن فتح محاولة هذا الطالب.');
      }

      final status = attemptData['status']?.toString() ?? '';

      if (status == 'submitted') {
        throw Exception('تم تسليم هذا الاختبار بالفعل.');
      }

      _quizEndAt = widget.quizEndAt;

      final quizDoc =
          await _firestore.collection('quizzes').doc(widget.quizId).get();

      if (quizDoc.exists) {
        final quizData = quizDoc.data();

        if (quizData != null) {
          _quizEndAt = _readDateTime(quizData['endAt']) ?? _quizEndAt;
        }
      }

      final quizQuestionsSnapshot = await _firestore
          .collection('quizQuestions')
          .where('quizId', isEqualTo: widget.quizId)
          .where('status', isEqualTo: 'published')
          .get();

      final links = quizQuestionsSnapshot.docs.map((doc) {
        final data = doc.data();

        return _QuestionLink(
          questionId: data['questionId']?.toString() ?? '',
          order: _readInt(data['order']) ?? 0,
        );
      }).where((link) => link.questionId.isNotEmpty).toList();

      links.sort((a, b) => a.order.compareTo(b.order));

      final questions = <_StudentQuestion>[];

      for (final link in links) {
        final questionDoc = await _firestore
            .collection('questions')
            .doc(link.questionId)
            .get();

        if (!questionDoc.exists) {
          continue;
        }

        final data = questionDoc.data();

        if (data == null) {
          continue;
        }

        final type = data['type']?.toString() ?? 'single_choice';

        final question = _StudentQuestion(
          id: questionDoc.id,
          text: data['text']?.toString() ?? '',
          type: type,
          options: _readStringList(data['options']),
          score: _readDouble(data['score']) ?? 0,
          timeLimitSeconds:
              _readInt(data['timeLimitSeconds']) ?? 0,
          maxCharacters:
              _readInt(data['maxCharacters']) ?? 0,
        );

        questions.add(question);

        if (type == 'essay') {
          _essayControllers[question.id] =
              TextEditingController();
        }
      }

      if (questions.isEmpty) {
        throw Exception('لا توجد أسئلة داخل هذا الاختبار.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _questions = questions;
        _loading = false;
      });

      await _loadExistingAnswers();
      _startCurrentQuestionTimer();
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل الأسئلة: ${e.message ?? e.code}';
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

  Future<void> _loadExistingAnswers() async {
    final snapshot = await _firestore
        .collection('answers')
        .where('attemptId', isEqualTo: widget.attemptId)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final questionId = data['questionId']?.toString();

      if (questionId == null || questionId.isEmpty) {
        continue;
      }

      _answers[questionId] = data['answer'];

      final controller = _essayControllers[questionId];

      if (controller != null) {
        final answer = data['answer']?.toString() ?? '';
        controller.text = answer;
      }
    }
  }

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }

  int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }

  double? _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  List<String> _readStringList(dynamic value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).toList();
    }

    return [];
  }

  _StudentQuestion get _currentQuestion =>
      _questions[_currentIndex];

  void _startCurrentQuestionTimer() {
    _timer?.cancel();

    if (_questions.isEmpty) {
      return;
    }

    final question = _currentQuestion;
    final now = DateTime.now();

    _questionStartedAt.putIfAbsent(question.id, () => now);

    DateTime? deadline;

    if (question.timeLimitSeconds > 0) {
      deadline = now.add(
        Duration(seconds: question.timeLimitSeconds),
      );
    }

    if (_quizEndAt != null) {
      if (deadline == null || _quizEndAt!.isBefore(deadline)) {
        deadline = _quizEndAt;
      }
    }

    _currentQuestionDeadline = deadline;

    if (deadline == null) {
      if (mounted) {
        setState(() {
          _remaining = Duration.zero;
        });
      }
      return;
    }

    _updateRemaining();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickTimer(),
    );
  }

  void _tickTimer() {
    if (!mounted) {
      return;
    }

    _updateRemaining();

    if (_remaining <= Duration.zero) {
      _timer?.cancel();
      _handleCurrentQuestionTimeout();
    }
  }

  void _updateRemaining() {
    if (_currentQuestionDeadline == null) {
      return;
    }

    final difference =
        _currentQuestionDeadline!.difference(DateTime.now());

    setState(() {
      _remaining =
          difference.isNegative ? Duration.zero : difference;
    });
  }

  Future<void> _handleCurrentQuestionTimeout() async {
    if (_submitting) {
      return;
    }

    await _saveCurrentAnswer(showMessage: false);

    if (!mounted) {
      return;
    }

    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
      });

      _startCurrentQuestionTimer();
      return;
    }

    await _submitQuiz(autoSubmit: true);
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 359999);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _selectSingleChoice(String value) async {
    setState(() {
      _answers[_currentQuestion.id] = value;
    });

    await _saveCurrentAnswer(showMessage: false);
  }

  Future<void> _toggleMultipleChoice(String value) async {
    final current =
        List<String>.from(_answers[_currentQuestion.id] ?? const []);

    if (current.contains(value)) {
      current.remove(value);
    } else {
      current.add(value);
    }

    setState(() {
      _answers[_currentQuestion.id] = current;
    });

    await _saveCurrentAnswer(showMessage: false);
  }

  Future<void> _setTrueFalse(bool value) async {
    setState(() {
      _answers[_currentQuestion.id] = value;
    });

    await _saveCurrentAnswer(showMessage: false);
  }

  void _setOrdering(List<String> values) {
    setState(() {
      _answers[_currentQuestion.id] = values;
    });
  }

  Future<void> _saveEssay() async {
    final controller =
        _essayControllers[_currentQuestion.id];

    if (controller == null) {
      return;
    }

    final text = controller.text.trim();

    if (_currentQuestion.maxCharacters > 0 &&
        text.length > _currentQuestion.maxCharacters) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الإجابة تتجاوز الحد الأقصى وهو '
            '${_currentQuestion.maxCharacters} حرف.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _answers[_currentQuestion.id] = text;
    });

    await _saveCurrentAnswer(showMessage: false);
  }

  Future<void> _saveCurrentAnswer({
    required bool showMessage,
  }) async {
    if (_questions.isEmpty) {
      return;
    }

    final studentId =
        widget.sessionManager.currentSession?.uid;

    if (studentId == null) {
      return;
    }

    final question = _currentQuestion;
    final answer = _answers[question.id];
    final startedAt =
        _questionStartedAt[question.id] ?? DateTime.now();
    final now = Timestamp.now();

    final answerRef = _firestore
        .collection('answers')
        .doc('${widget.attemptId}_${question.id}');

    try {
      await answerRef.set({
        'attemptId': widget.attemptId,
        'questionId': question.id,
        'studentId': studentId,
        'answer': answer,
        'startedAt': Timestamp.fromDate(startedAt),
        'answeredAt': now,
        'status': 'answered',
        'createdAt': now,
      }, SetOptions(merge: true));

      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الإجابة.'),
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر حفظ الإجابة: ${e.message ?? e.code}',
          ),
        ),
      );
    }
  }

  Future<void> _goNext() async {
    await _saveCurrentAnswer(showMessage: false);

    if (!mounted) {
      return;
    }

    if (_currentIndex >= _questions.length - 1) {
      await _confirmSubmit();
      return;
    }

    setState(() {
      _currentIndex++;
    });

    _startCurrentQuestionTimer();
  }

  Future<void> _goPrevious() async {
    await _saveCurrentAnswer(showMessage: false);

    if (!mounted || _currentIndex == 0) {
      return;
    }

    setState(() {
      _currentIndex--;
    });

    _startCurrentQuestionTimer();
  }

  Future<void> _confirmSubmit() async {
    if (!mounted) {
      return;
    }

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إنهاء الاختبار'),
            content: const Text(
              'هل أنت متأكد من تسليم الاختبار؟ '
              'لن تتمكن من تعديل الإجابات بعد التسليم.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(true),
                child: const Text('تسليم الاختبار'),
              ),
            ],
          ),
        );
      },
    );

    if (shouldSubmit == true) {
      await _submitQuiz(autoSubmit: false);
    }
  }

  Future<void> _submitQuiz({
    required bool autoSubmit,
  }) async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await _saveCurrentAnswer(showMessage: false);

      final now = Timestamp.now();

      await _firestore
          .collection('attempts')
          .doc(widget.attemptId)
          .update({
        'submittedAt': now,
        'status': 'submitted',
      });

      _timer?.cancel();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            autoSubmit
                ? 'انتهى وقت الاختبار وتم تسليمه تلقائيًا.'
                : 'تم تسليم الاختبار بنجاح.',
          ),
        ),
      );

      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر تسليم الاختبار: ${e.message ?? e.code}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر تسليم الاختبار: '
            '${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Widget _buildProgress(BuildContext context) {
    final progress =
        (_currentIndex + 1) / _questions.length;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'السؤال ${_currentIndex + 1} من ${_questions.length}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_currentQuestionDeadline != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _remaining.inSeconds <= 10
                      ? colorScheme.errorContainer
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _formatDuration(_remaining),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _remaining.inSeconds <= 10
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: progress),
      ],
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final question = _currentQuestion;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              question.text,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildAnswerWidget(context, question),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerWidget(
    BuildContext context,
    _StudentQuestion question,
  ) {
    switch (question.type) {
      case 'single_choice':
        return _buildSingleChoice(question);

      case 'multiple_choice':
        return _buildMultipleChoice(question);

      case 'true_false':
        return _buildTrueFalse(question);

      case 'essay':
        return _buildEssay(question);

      case 'ordering':
        return _buildOrdering(question);

      default:
        return const Text(
          'نوع السؤال غير مدعوم.',
          textAlign: TextAlign.center,
        );
    }
  }

  Widget _buildSingleChoice(_StudentQuestion question) {
    final selected = _answers[question.id]?.toString();

    return Column(
      children: question.options.map((option) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: RadioListTile<String>(
            value: option,
            groupValue: selected,
            title: Text(option),
            onChanged: (value) {
              if (value != null) {
                _selectSingleChoice(value);
              }
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultipleChoice(_StudentQuestion question) {
    final selected =
        List<String>.from(_answers[question.id] ?? const []);

    return Column(
      children: question.options.map((option) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: CheckboxListTile(
            value: selected.contains(option),
            title: Text(option),
            onChanged: (_) {
              _toggleMultipleChoice(option);
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTrueFalse(_StudentQuestion question) {
    final value = _answers[question.id];

    return Column(
      children: [
        Card(
          child: RadioListTile<bool>(
            value: true,
            groupValue: value is bool ? value : null,
            title: const Text('صح'),
            onChanged: (selected) {
              if (selected != null) {
                _setTrueFalse(selected);
              }
            },
          ),
        ),
        Card(
          child: RadioListTile<bool>(
            value: false,
            groupValue: value is bool ? value : null,
            title: const Text('خطأ'),
            onChanged: (selected) {
              if (selected != null) {
                _setTrueFalse(selected);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEssay(_StudentQuestion question) {
    final controller = _essayControllers[question.id];

    if (controller == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          maxLines: 8,
          maxLength: question.maxCharacters > 0
              ? question.maxCharacters
              : null,
          decoration: const InputDecoration(
            labelText: 'اكتب إجابتك',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            _answers[question.id] = value;
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saveEssay,
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ الإجابة'),
        ),
      ],
    );
  }

  Widget _buildOrdering(_StudentQuestion question) {
    final selected =
        List<String>.from(_answers[question.id] ?? const []);

    final remaining = question.options
        .where((option) => !selected.contains(option))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'اضغط على الاختيارات بالترتيب المطلوب:',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (selected.isNotEmpty) ...[
          const Text(
            'الترتيب الحالي:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...selected.asMap().entries.map((entry) {
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text('${entry.key + 1}'),
                ),
                title: Text(entry.value),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    final newList = List<String>.from(selected)
                      ..removeAt(entry.key);
                    _setOrdering(newList);
                  },
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
        ],
        ...remaining.map((option) {
          return OutlinedButton(
            onPressed: () {
              final newList = List<String>.from(selected)
                ..add(option);
              _setOrdering(newList);
            },
            child: Text(option),
          );
        }),
      ],
    );
  }

  Widget _buildNavigation(BuildContext context) {
    final isLast = _currentIndex == _questions.length - 1;

    return Row(
      children: [
        if (_currentIndex > 0)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _submitting ? null : _goPrevious,
              icon: const Icon(Icons.arrow_back),
              label: const Text('السابق'),
            ),
          ),
        if (_currentIndex > 0)
          const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: _submitting ? null : _goNext,
            icon: Icon(
              isLast
                  ? Icons.check_circle_outline
                  : Icons.arrow_forward,
            ),
            label: Text(
              isLast ? 'إنهاء وتسليم الاختبار' : 'التالي',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildProgress(context),
        const SizedBox(height: 16),
        _buildQuestion(context),
        const SizedBox(height: 16),
        _buildNavigation(context),
        if (_submitting) ...[
          const SizedBox(height: 16),
          const Center(
            child: CircularProgressIndicator(),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _submitting) {
          return;
        }

        _confirmLeave();
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.quizTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: _buildBody(context),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('الخروج من الاختبار'),
            content: const Text(
              'إذا خرجت الآن سيظل الاختبار مفتوحًا ولن يتم تسليمه. '
              'هل تريد الخروج؟',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(false),
                child: const Text('البقاء'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(true),
                child: const Text('خروج'),
              ),
            ],
          ),
        );
      },
    );

    if (leave == true && mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _QuestionLink {
  final String questionId;
  final int order;

  const _QuestionLink({
    required this.questionId,
    required this.order,
  });
}

class _StudentQuestion {
  final String id;
  final String text;
  final String type;
  final List<String> options;
  final double score;
  final int timeLimitSeconds;
  final int maxCharacters;

  const _StudentQuestion({
    required this.id,
    required this.text,
    required this.type,
    required this.options,
    required this.score,
    required this.timeLimitSeconds,
    required this.maxCharacters,
  });
}

class _StudentQuiz {
  final String id;
  final String title;
  final String description;
  final String subjectId;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime createdAt;
  final String? attemptStatus;

  const _StudentQuiz({
    required this.id,
    required this.title,
    required this.description,
    required this.subjectId,
    required this.startAt,
    required this.endAt,
    required this.createdAt,
    required this.attemptStatus,
  });
}
