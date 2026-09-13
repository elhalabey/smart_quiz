import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';
import 'student_result_details_screen.dart';

class StudentResultsScreen extends StatefulWidget {
  const StudentResultsScreen({
    super.key,
    required this.sessionManager,
  });

  final SessionManager sessionManager;

  @override
  State<StudentResultsScreen> createState() => _StudentResultsScreenState();
}

class _StudentResultsScreenState extends State<StudentResultsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  String? _errorMessage;
  List<StudentResult> _results = [];
  final Map<String, String> _quizTitles = {};

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
      final studentId = widget.sessionManager.currentSession?.uid;

      if (studentId == null || studentId.isEmpty) {
        throw Exception('لم يتم العثور على جلسة الطالب.');
      }

      final snapshot = await _firestore
          .collection('results')
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: 'published')
          .get();

      final results = <StudentResult>[];
      final quizIds = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final quizId = data['quizId']?.toString() ?? '';

        if (quizId.isNotEmpty) {
          quizIds.add(quizId);
        }

        results.add(
          StudentResult(
            id: doc.id,
            attemptId: data['attemptId']?.toString() ?? '',
            quizId: quizId,
            studentId: data['studentId']?.toString() ?? '',
            autoScore: _readDouble(data['autoScore']) ?? 0,
            manualScore: _readDouble(data['manualScore']) ?? 0,
            totalScore: _readDouble(data['totalScore']) ?? 0,
            maxScore: _readDouble(data['maxScore']) ?? 0,
            status: data['status']?.toString() ?? 'published',
            publishedAt: _readDateTime(data['publishedAt']),
          ),
        );
      }

      _quizTitles.clear();

      for (final quizId in quizIds) {
        final quizDoc = await _firestore
            .collection('quizzes')
            .doc(quizId)
            .get();

        if (!quizDoc.exists) {
          continue;
        }

        final data = quizDoc.data();
        if (data == null) {
          continue;
        }

        _quizTitles[quizId] = data['title']?.toString() ?? 'اختبار';
      }

      results.sort((a, b) {
        final aDate = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

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
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _openResultDetails(StudentResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentResultDetailsScreen(
          sessionManager: widget.sessionManager,
          resultId: result.id,
        ),
      ),
    );
  }

  Widget _buildResultCard(StudentResult result) {
    final percentage = result.maxScore > 0
        ? (result.totalScore / result.maxScore) * 100
        : 0.0;

    final quizTitle = _quizTitles[result.quizId] ?? 'اختبار';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openResultDetails(result),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: const Icon(Icons.assessment_outlined),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      quizTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_left),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              _buildInfoRow(
                'الدرجة النهائية',
                '${_formatNumber(result.totalScore)} / ${_formatNumber(result.maxScore)}',
                Icons.score_outlined,
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'النسبة',
                '${percentage.toStringAsFixed(1)}%',
                Icons.percent_outlined,
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'التصحيح التلقائي',
                _formatNumber(result.autoScore),
                Icons.auto_fix_high_outlined,
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'التصحيح اليدوي',
                _formatNumber(result.manualScore),
                Icons.edit_outlined,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'النتيجة منشورة',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  if (result.publishedAt != null)
                    Text(
                      _formatDate(result.publishedAt!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'اضغط لعرض الأسئلة وإجاباتك',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 19,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
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
            Icon(Icons.assessment_outlined, size: 64),
            SizedBox(height: 16),
            Center(
              child: Text(
                'لا توجد نتائج منشورة حتى الآن.',
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
          title: const Text(
            'نتائجي',
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

  static double? _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(2);
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }
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
  });
}
