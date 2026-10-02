import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../quizzes/exam_print_service.dart';
import '../../../../core/session/session_manager.dart';

class TeacherQuizQuestionsScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final String quizId;
  final String quizTitle;
  final String subjectId;

  const TeacherQuizQuestionsScreen({
    super.key,
    required this.sessionManager,
    required this.quizId,
    required this.quizTitle,
    required this.subjectId,
  });

  @override
  State<TeacherQuizQuestionsScreen> createState() =>
      _TeacherQuizQuestionsScreenState();
}

class _TeacherQuizQuestionsScreenState
    extends State<TeacherQuizQuestionsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  String _searchText = '';
  String _selectedType = 'all';
  String _selectedSort = 'newest';

  List<_BankQuestion> _allQuestions = [];
  List<_BankQuestion> _filteredQuestions = [];
  List<_BankQuestion> _selectedQuestions = [];

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
Future<void> _printExam() async {
  if (_selectedQuestions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('لا توجد أسئلة داخل الاختبار للطباعة.'),
      ),
    );
    return;
  }

  try {
    final questions = <PrintQuestion>[];

    for (var i = 0; i < _selectedQuestions.length; i++) {
      final question = _selectedQuestions[i];

      questions.add(
        PrintQuestion(
          number: i + 1,
          text: question.text,
          type: question.type,
          options: question.options,
          score: question.score,
        ),
      );
    }

    await printExam(
      title: widget.quizTitle,
      subject: widget.subjectId,
      questions: questions,
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تعذر طباعة الامتحان: ${e.toString().replaceFirst('Exception: ', '')}',
        ),
      ),
    );
  }
}
  Future<void> _loadQuestions() async {
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

      final questionSnapshot = await _firestore
          .collection('questions')
          .where('teacherId', isEqualTo: teacherId)
          .where('subjectId', isEqualTo: widget.subjectId)
          .get();

      final questions = questionSnapshot.docs
          .map((doc) {
            final data = doc.data();
            return _BankQuestion(
  id: doc.id,
  text: data['text']?.toString() ?? '',
  type: data['type']?.toString() ?? 'single_choice',
  options: _readStringList(data['options']),
  score: _readDouble(data['score']) ?? 0,
  timeLimitSeconds: _readInt(data['timeLimitSeconds']) ?? 0,
  createdAt: _readDateTime(data['createdAt']),
);
          })
          .where((question) => question.text.trim().isNotEmpty)
          .toList();

      final linkSnapshot = await _firestore
          .collection('quizQuestions')
          .where('quizId', isEqualTo: widget.quizId)
          .get();

      final links = <String, int>{};
      for (final doc in linkSnapshot.docs) {
        final data = doc.data();
        final questionId = data['questionId']?.toString() ?? '';
        if (questionId.isNotEmpty) {
          links[questionId] = _readInt(data['order']) ?? 0;
        }
      }

      final byId = <String, _BankQuestion>{
        for (final question in questions) question.id: question,
      };

      final selected = <_BankQuestion>[];
      final orderedLinks = links.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      for (final entry in orderedLinks) {
        final question = byId[entry.key];
        if (question != null) selected.add(question);
      }

      if (!mounted) return;

      setState(() {
        _allQuestions = questions;
        _selectedQuestions = selected;
        _loading = false;
      });
      _applyFilters();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل بنك الأسئلة: ${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
List<String> _readStringList(dynamic value) {
  if (value is Iterable) {
    return value.map((item) => item.toString()).toList();
  }

  return [];
}
  void _applyFilters() {
    final search = _searchText.trim().toLowerCase();

    final filtered = _allQuestions.where((question) {
      final matchesType =
          _selectedType == 'all' || question.type == _selectedType;
      final matchesSearch =
          search.isEmpty || question.text.toLowerCase().contains(search);
      final notSelected = !_selectedQuestions.any(
        (selected) => selected.id == question.id,
      );
      return matchesType && matchesSearch && notSelected;
    }).toList();

    filtered.sort((a, b) {
      switch (_selectedSort) {
        case 'oldest':
          return _dateValue(a.createdAt).compareTo(_dateValue(b.createdAt));
        case 'type':
          final typeCompare = _typeLabel(a.type).compareTo(_typeLabel(b.type));
          return typeCompare != 0 ? typeCompare : a.text.compareTo(b.text);
        case 'newest':
        default:
          return _dateValue(b.createdAt).compareTo(_dateValue(a.createdAt));
      }
    });

    if (mounted) {
      setState(() => _filteredQuestions = filtered);
    }
  }

  void _addQuestion(_BankQuestion question) {
    if (_selectedQuestions.any((item) => item.id == question.id)) return;
    setState(() => _selectedQuestions.add(question));
    _applyFilters();
  }

  void _removeQuestion(String questionId) {
    setState(() {
      _selectedQuestions.removeWhere((question) => question.id == questionId);
    });
    _applyFilters();
  }

  void _reorderSelected(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _selectedQuestions.removeAt(oldIndex);
      _selectedQuestions.insert(newIndex, item);
    });
  }

  Future<void> _saveSelection() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final teacherId = widget.sessionManager.currentSession?.uid;
      if (teacherId == null) {
        throw Exception('لم يتم العثور على جلسة المعلم.');
      }

      final quizDoc = await _firestore.collection('quizzes').doc(widget.quizId).get();
      if (!quizDoc.exists) throw Exception('لم يتم العثور على الاختبار.');

      final quizData = quizDoc.data();
      if (quizData == null || quizData['teacherId']?.toString() != teacherId) {
        throw Exception('لا يمكنك تعديل أسئلة هذا الاختبار.');
      }
      if (quizData['subjectId']?.toString() != widget.subjectId) {
        throw Exception('مادة الاختبار لا تطابق مادة بنك الأسئلة.');
      }

      final existing = await _firestore
          .collection('quizQuestions')
          .where('quizId', isEqualTo: widget.quizId)
          .get();

      final batch = _firestore.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }

      for (var index = 0; index < _selectedQuestions.length; index++) {
        final question = _selectedQuestions[index];
        final ref = _firestore
            .collection('quizQuestions')
            .doc('${widget.quizId}_${question.id}');
        batch.set(ref, {
          'quizId': widget.quizId,
          'questionId': question.id,
          'order': index + 1,
          'status': quizData['status']?.toString() ?? 'draft',
          'teacherId': teacherId,
          'subjectId': widget.subjectId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedQuestions.isEmpty
                ? 'تم حفظ الاختبار بدون أسئلة'
                : 'تم حفظ ${_selectedQuestions.length} سؤالًا داخل الاختبار',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ أسئلة الاختبار: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'essay': return 'مقالي';
      case 'true_false': return 'صح / خطأ';
      case 'single_choice': return 'اختيار واحد';
      case 'multiple_choice': return 'اختيارات متعددة';
      case 'ordering': return 'ترتيب';
      default: return type;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'essay': return Icons.edit_note_outlined;
      case 'true_false': return Icons.rule_outlined;
      case 'single_choice': return Icons.radio_button_checked_outlined;
      case 'multiple_choice': return Icons.check_box_outlined;
      case 'ordering': return Icons.swap_vert_outlined;
      default: return Icons.help_outline;
    }
  }

  Color _typeColor(BuildContext context, String type) {
    final colors = Theme.of(context).colorScheme;
    switch (type) {
      case 'essay': return colors.tertiary;
      case 'true_false': return colors.primary;
      case 'single_choice': return colors.secondary;
      case 'multiple_choice': return colors.primaryContainer;
      case 'ordering': return colors.error;
      default: return colors.outline;
    }
  }

  DateTime _dateValue(DateTime? value) =>
      value ?? DateTime.fromMillisecondsSinceEpoch(0);

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _readInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _buildFilters(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) {
                _searchText = value;
                _applyFilters();
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchText.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          _searchController.clear();
                          _searchText = '';
                          _applyFilters();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                labelText: 'بحث في نص السؤال',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'نوع السؤال',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('كل الأنواع')),
                      DropdownMenuItem(value: 'single_choice', child: Text('اختيار واحد')),
                      DropdownMenuItem(value: 'multiple_choice', child: Text('اختيارات متعددة')),
                      DropdownMenuItem(value: 'true_false', child: Text('صح / خطأ')),
                      DropdownMenuItem(value: 'essay', child: Text('مقالي')),
                      DropdownMenuItem(value: 'ordering', child: Text('ترتيب')),
                    ],
                    onChanged: _saving ? null : (value) {
                      if (value == null) return;
                      setState(() => _selectedType = value);
                      _applyFilters();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedSort,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الترتيب',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('الأحدث')),
                      DropdownMenuItem(value: 'oldest', child: Text('الأقدم')),
                      DropdownMenuItem(value: 'type', child: Text('حسب النوع')),
                    ],
                    onChanged: _saving ? null : (value) {
                      if (value == null) return;
                      setState(() => _selectedSort = value);
                      _applyFilters();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankCard(BuildContext context, _BankQuestion question) {
    final typeColor = _typeColor(context, question.type);
    return Card(
      key: ValueKey('bank_${question.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Draggable<_BankQuestion>(
        data: question,
        feedback: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(question.text, maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: _bankCardContent(context, question, typeColor),
        ),
        child: InkWell(
          onTap: _saving ? null : () => _addQuestion(question),
          borderRadius: BorderRadius.circular(12),
          child: _bankCardContent(context, question, typeColor),
        ),
      ),
    );
  }

  Widget _bankCardContent(
    BuildContext context,
    _BankQuestion question,
    Color typeColor,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(_typeIcon(question.type), color: typeColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _InfoChip(label: _typeLabel(question.type)),
                    _InfoChip(label: 'الدرجة: ${question.score}'),
                    if (question.timeLimitSeconds > 0)
                      _InfoChip(label: 'الوقت: ${question.timeLimitSeconds}ث'),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.add_circle_outline, size: 22),
        ],
      ),
    );
  }

  Widget _buildBankPane(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.library_books_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'بنك الأسئلة',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Text('${_filteredQuestions.length}'),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _filteredQuestions.isEmpty
                  ? const Center(
                      child: Text('لا توجد أسئلة مطابقة للفلاتر.', textAlign: TextAlign.center),
                    )
                  : ListView.builder(
                      itemCount: _filteredQuestions.length,
                      itemBuilder: (context, index) =>
                          _buildBankCard(context, _filteredQuestions[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPane(BuildContext context) {
    return DragTarget<_BankQuestion>(
      onWillAcceptWithDetails: (details) => !_selectedQuestions.any(
        (question) => question.id == details.data.id,
      ),
      onAcceptWithDetails: (details) => _addQuestion(details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        final colorScheme = Theme.of(context).colorScheme;

        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: highlighted
                ? BorderSide(color: colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.quiz_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'أسئلة الاختبار',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    CircleAvatar(
                      radius: 14,
                      child: Text('${_selectedQuestions.length}', style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'اضغط على سؤال لإضافته، أو اسحبه هنا. اسحب الأسئلة المختارة لأعلى أو لأسفل لتغيير ترتيبها.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _selectedQuestions.isEmpty
                      ? Center(
                          child: Text(
                            'لم تتم إضافة أسئلة بعد',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: _selectedQuestions.length,
                          onReorder: _reorderSelected,
                          itemBuilder: (context, index) {
                            final question = _selectedQuestions[index];
                            return Card(
                              key: ValueKey('selected_${question.id}'),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(child: Text('${index + 1}')),
                                title: Text(question.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                                subtitle: Text(_typeLabel(question.type)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.drag_handle),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'إزالة',
                                      onPressed: _saving ? null : () => _removeQuestion(question.id),
                                      icon: const Icon(Icons.remove_circle_outline),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('أسئلة الاختبار: ${widget.quizTitle}', style: const TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: [
  IconButton(
    tooltip: 'طباعة الامتحان',
    onPressed: _loading || _saving || _selectedQuestions.isEmpty
        ? null
        : _printExam,
    icon: const Icon(Icons.print_outlined),
  ),
  IconButton(
    tooltip: 'إعادة تحميل',
    onPressed: _loading || _saving ? null : _loadQuestions,
    icon: const Icon(Icons.refresh),
  ),
],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_errorMessage!, textAlign: TextAlign.center)))
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _buildFilters(context),
                          const SizedBox(height: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                if (constraints.maxWidth >= 800) {
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(flex: 5, child: _buildBankPane(context)),
                                      const SizedBox(width: 12),
                                      Expanded(flex: 5, child: _buildSelectedPane(context)),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    SizedBox(height: 390, child: _buildBankPane(context)),
                                    const SizedBox(height: 12),
                                    Expanded(child: _buildSelectedPane(context)),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _saveSelection,
                              icon: _saving
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.save_outlined),
                              label: Text(_saving ? 'جاري حفظ الأسئلة...' : 'حفظ أسئلة الاختبار (${_selectedQuestions.length})'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _BankQuestion {
  final String id;
  final String text;
  final String type;
  final List<String> options;
  final double score;
  final int timeLimitSeconds;
  final DateTime? createdAt;

  const _BankQuestion({
    required this.id,
    required this.text,
    required this.type,
    required this.options,
    required this.score,
    required this.timeLimitSeconds,
    required this.createdAt,
  });
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
