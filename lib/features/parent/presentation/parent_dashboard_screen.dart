import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _loading = true;
  String? _errorMessage;

  List<_ParentChild> _children = [];
  _ParentChild? _selectedChild;
  List<_ParentQuiz> _quizzes = [];

  @override
  void initState() {
    super.initState();
    _loadParentData();
  }

  Future<void> _loadParentData() async {
    final user = _auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'لم يتم العثور على حساب ولي الأمر.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final links = await _firestore
          .collection('parentStudents')
          .where('parentId', isEqualTo: user.uid)
          .get();

      final children = <_ParentChild>[];

      for (final link in links.docs) {
        final data = link.data();
        final studentId = data['studentId']?.toString();

        if (studentId == null || studentId.isEmpty) {
          continue;
        }

        final studentDoc =
            await _firestore.collection('students').doc(studentId).get();

        if (!studentDoc.exists) {
          continue;
        }

        final studentData = studentDoc.data();

        if (studentData == null) {
          continue;
        }

        children.add(
          _ParentChild(
            id: studentId,
            name: (studentData['name'] ?? 'بدون اسم').toString(),
            studentCode:
                (studentData['studentCode'] ?? 'غير متوفر').toString(),
            classId: (studentData['classId'] ?? '').toString(),
            relationship:
                (data['relationship'] ?? 'ولي الأمر').toString(),
          ),
        );
      }

      if (!mounted) return;

      if (children.isEmpty) {
        setState(() {
          _children = [];
          _selectedChild = null;
          _quizzes = [];
          _loading = false;
        });
        return;
      }

      final selectedChild = _selectedChild == null
          ? children.first
          : children.firstWhere(
              (child) => child.id == _selectedChild!.id,
              orElse: () => children.first,
            );

      setState(() {
        _children = children;
        _selectedChild = selectedChild;
      });

      await _loadChildQuizzes(selectedChild);

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل بيانات ولي الأمر:\n${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل بيانات ولي الأمر:\n$e';
      });
    }
  }

  Future<void> _loadChildQuizzes(_ParentChild child) async {
    final quizClassesSnapshot = await _firestore
        .collection('quizClasses')
        .where('classId', isEqualTo: child.classId)
        .get();

    final quizIds = quizClassesSnapshot.docs
        .map((doc) => doc.data()['quizId']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final resultsSnapshot = await _firestore
        .collection('results')
        .where('studentId', isEqualTo: child.id)
        .get();

    final resultByQuizId = <String, _ParentResult>{};

    for (final resultDoc in resultsSnapshot.docs) {
      final data = resultDoc.data();
      final quizId = data['quizId']?.toString() ?? '';

      if (quizId.isEmpty) {
        continue;
      }

      resultByQuizId[quizId] = _ParentResult(
        quizId: quizId,
        totalScore: _toDouble(data['totalScore']),
        maxScore: _toDouble(data['maxScore']),
        status: data['status']?.toString() ?? '',
      );
    }

    final quizzes = <_ParentQuiz>[];
    final subjectCache = <String, String>{};

    for (final quizId in quizIds) {
      final quizDoc =
          await _firestore.collection('quizzes').doc(quizId).get();

      if (!quizDoc.exists) {
        continue;
      }

      final data = quizDoc.data();

      if (data == null || data['status']?.toString() != 'published') {
        continue;
      }

      final title = data['title']?.toString().trim() ?? '';
      final subjectId = data['subjectId']?.toString() ?? '';

      String subjectName = 'مادة غير محددة';

      if (subjectId.isNotEmpty) {
        if (subjectCache.containsKey(subjectId)) {
          subjectName = subjectCache[subjectId]!;
        } else {
          final subjectDoc = await _firestore
              .collection('subjects')
              .doc(subjectId)
              .get();

          final subjectData = subjectDoc.data();

          subjectName =
              subjectData?['nameAr']?.toString().trim() ?? '';

          if (subjectName.isEmpty) {
            subjectName =
                subjectData?['nameEn']?.toString().trim() ?? '';
          }

          if (subjectName.isEmpty) {
            subjectName = 'مادة غير محددة';
          }

          subjectCache[subjectId] = subjectName;
        }
      }

      final result = resultByQuizId[quizId];

      quizzes.add(
        _ParentQuiz(
          id: quizId,
          title: title.isEmpty ? 'اختبار' : title,
          subjectName: subjectName,
          startAt: _readDateTime(data['startAt']),
          endAt: _readDateTime(data['endAt']),
          createdAt: _readDateTime(data['createdAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          submitted: result != null,
          totalScore: result?.totalScore,
          maxScore: result?.maxScore,
          resultStatus: result?.status,
        ),
      );
    }

    quizzes.sort((a, b) {
      final aDate = a.startAt ?? a.createdAt;
      final bDate = b.startAt ?? b.createdAt;
      return bDate.compareTo(aDate);
    });

    if (!mounted) return;

    setState(() {
      _selectedChild = child;
      _quizzes = quizzes;
    });
  }

  Future<void> _selectChild(_ParentChild child) async {
    setState(() {
      _selectedChild = child;
      _loading = true;
      _errorMessage = null;
    });

    try {
      await _loadChildQuizzes(child);

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل اختبارات الطالب:\n'
            '${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل اختبارات الطالب:\n$e';
      });
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatScore(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(2);
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

  String _getQuizStatus(_ParentQuiz quiz) {
    if (quiz.submitted) {
      return 'تم التسليم';
    }

    final now = DateTime.now();

    if (quiz.startAt != null && now.isBefore(quiz.startAt!)) {
      return 'لم يبدأ';
    }

    if (quiz.endAt != null && now.isAfter(quiz.endAt!)) {
      return 'لم يتم التسليم';
    }

    return 'لم يتم التسليم';
  }

  Color _getStatusColor(BuildContext context, _ParentQuiz quiz) {
    final colorScheme = Theme.of(context).colorScheme;

    if (quiz.submitted) {
      return colorScheme.primary;
    }

    return colorScheme.error;
  }

  Widget _buildQuizCard(
    BuildContext context,
    _ParentQuiz quiz,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = _getQuizStatus(quiz);
    final statusColor = _getStatusColor(context, quiz);

    String scoreText;

    if (!quiz.submitted) {
      scoreText = 'الدرجة: —';
    } else if (quiz.resultStatus == 'published' &&
        quiz.totalScore != null &&
        quiz.maxScore != null) {
      scoreText =
          'الدرجة: ${_formatScore(quiz.totalScore!)} / '
          '${_formatScore(quiz.maxScore!)}';
    } else {
      scoreText = 'الدرجة: لم تُنشر بعد';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Icon(
                quiz.submitted
                    ? Icons.assignment_turned_in_outlined
                    : Icons.assignment_outlined,
              ),
            ),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 6),
                  Text(
                    'المادة: ${quiz.subjectName}',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(scoreText),
                  const SizedBox(height: 4),
                  Text(
                    'البداية: ${_formatDateTime(quiz.startAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'النهاية: ${_formatDateTime(quiz.endAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 52,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadParentData,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_children.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'لا يوجد أبناء مرتبطون بحساب ولي الأمر.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              value: _selectedChild?.id,
              decoration: const InputDecoration(
                labelText: 'الطالب',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              items: _children.map((child) {
                return DropdownMenuItem<String>(
                  value: child.id,
                  child: Text(child.name),
                );
              }).toList(),
              onChanged: (studentId) {
                if (studentId == null) return;

                final child = _children.firstWhere(
                  (item) => item.id == studentId,
                );

                _selectChild(child);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_selectedChild != null)
          Row(
            children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'متابعة اختبارات ${_selectedChild!.name}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _loadParentData,
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        const SizedBox(height: 10),
        if (_quizzes.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'لا توجد اختبارات منشورة لهذا الطالب حاليًا.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _quizzes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _buildQuizCard(
                  context,
                  _quizzes[index],
                );
              },
            ),
          ),
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
            'متابعة الطالب',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }
}

class _ParentChild {
  final String id;
  final String name;
  final String studentCode;
  final String classId;
  final String relationship;

  const _ParentChild({
    required this.id,
    required this.name,
    required this.studentCode,
    required this.classId,
    required this.relationship,
  });
}

class _ParentQuiz {
  final String id;
  final String title;
  final String subjectName;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime createdAt;
  final bool submitted;
  final double? totalScore;
  final double? maxScore;
  final String? resultStatus;

  const _ParentQuiz({
    required this.id,
    required this.title,
    required this.subjectName,
    required this.startAt,
    required this.endAt,
    required this.createdAt,
    required this.submitted,
    required this.totalScore,
    required this.maxScore,
    required this.resultStatus,
  });
}

class _ParentResult {
  final String quizId;
  final double totalScore;
  final double maxScore;
  final String status;

  const _ParentResult({
    required this.quizId,
    required this.totalScore,
    required this.maxScore,
    required this.status,
  });
}
