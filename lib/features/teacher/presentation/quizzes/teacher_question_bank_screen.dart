import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// بنك الأسئلة الخاص بالمعلم.
///
/// الاستخدام:
/// - يعرض أسئلة المعلم فقط.
/// - يدعم البحث في نص السؤال.
/// - يدعم الفلترة حسب المادة ونوع السؤال.
/// - يدعم الترتيب حسب الأحدث/الأقدم/النوع.
/// - يعرض معلومات مختصرة عن كل سؤال.
/// - onAddQuestion و onEditQuestion اختياريان حتى يمكن ربط الشاشة
///   لاحقًا بشاشات الإضافة والتعديل الحالية بدون تعديل هذا الملف.
class TeacherQuestionBankScreen extends StatefulWidget {
  final VoidCallback? onAddQuestion;
  final void Function(String questionId, Map<String, dynamic> questionData)?
      onEditQuestion;

  const TeacherQuestionBankScreen({
    super.key,
    this.onAddQuestion,
    this.onEditQuestion,
  });

  @override
  State<TeacherQuestionBankScreen> createState() =>
      _TeacherQuestionBankScreenState();
}

class _TeacherQuestionBankScreenState
    extends State<TeacherQuestionBankScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _searchController = TextEditingController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allQuestions = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredQuestions = [];

  final Map<String, String> _subjectNames = {};

  String _selectedSubjectId = '';
  String _selectedType = 'all';
  String _selectedSort = 'newest';

  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    _loadQuestionBank();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applyFilters)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadQuestionBank() async {
    final teacherId = _auth.currentUser?.uid;

    if (teacherId == null) {
      setState(() {
        _loading = false;
        _errorMessage = 'لم يتم العثور على جلسة المعلم.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // نقرأ أسئلة المعلم فقط.
      // الفلترة حسب المادة والنوع تتم محليًا حتى لا نحتاج
      // إلى إنشاء Composite Index لكل تركيبة من الفلاتر.
      final questionsSnapshot = await _firestore
          .collection('questions')
          .where('teacherId', isEqualTo: teacherId)
          .get();

      await _loadSubjects(teacherId);

      if (!mounted) {
        return;
      }

      setState(() {
        _allQuestions = questionsSnapshot.docs;
        _filteredQuestions = List.from(questionsSnapshot.docs);
        _loading = false;
      });

      _applyFilters();
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'حدث خطأ أثناء تحميل بنك الأسئلة: ${e.message ?? e.code}';
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

  Future<void> _loadSubjects(String teacherId) async {
    try {
      final subjectsSnapshot = await _firestore
          .collection('subjects')
          .where('active', isEqualTo: true)
          .get();

      _subjectNames.clear();

      for (final doc in subjectsSnapshot.docs) {
        final data = doc.data();
        final nameAr = data['nameAr']?.toString().trim() ?? '';
        final nameEn = data['nameEn']?.toString().trim() ?? '';

        _subjectNames[doc.id] = nameAr.isNotEmpty
            ? nameAr
            : (nameEn.isNotEmpty ? nameEn : doc.id);
      }

      // إذا كان هناك سؤال لم تعد مادته موجودة/نشطة،
      // نعرض اسم المادة المخزن في السؤال كحل احتياطي.
      for (final question in _allQuestions) {
        final data = question.data();
        final subjectId = data['subjectId']?.toString() ?? '';

        if (subjectId.isNotEmpty && !_subjectNames.containsKey(subjectId)) {
          _subjectNames[subjectId] = subjectId;
        }
      }
    } on FirebaseException {
      // عدم تحميل أسماء المواد لا يمنع عرض بنك الأسئلة.
      _subjectNames.clear();

      for (final question in _allQuestions) {
        final data = question.data();
        final subjectId = data['subjectId']?.toString() ?? '';

        if (subjectId.isNotEmpty) {
          _subjectNames[subjectId] = subjectId;
        }
      }
    }
  }

  void _applyFilters() {
    if (!mounted) {
      return;
    }

    final search = _searchController.text.trim().toLowerCase();

    final filtered = _allQuestions.where((doc) {
      final data = doc.data();

      final text = data['text']?.toString().toLowerCase() ?? '';
      final subjectId = data['subjectId']?.toString() ?? '';
      final type = data['type']?.toString() ?? '';

      final matchesSearch =
          search.isEmpty || text.contains(search);

      final matchesSubject =
          _selectedSubjectId.isEmpty ||
          subjectId == _selectedSubjectId;

      final matchesType =
          _selectedType == 'all' ||
          type == _selectedType;

      return matchesSearch && matchesSubject && matchesType;
    }).toList();

    filtered.sort((a, b) {
      final aData = a.data();
      final bData = b.data();

      switch (_selectedSort) {
        case 'oldest':
          return _readDate(aData['createdAt'])
              .compareTo(_readDate(bData['createdAt']));

        case 'type':
          final aType = _typeLabel(
            aData['type']?.toString() ?? '',
          );
          final bType = _typeLabel(
            bData['type']?.toString() ?? '',
          );

          final typeCompare = aType.compareTo(bType);
          if (typeCompare != 0) {
            return typeCompare;
          }

          return _readDate(bData['createdAt'])
              .compareTo(_readDate(aData['createdAt']));

        case 'newest':
        default:
          return _readDate(bData['createdAt'])
              .compareTo(_readDate(aData['createdAt']));
      }
    });

    setState(() {
      _filteredQuestions = filtered;
    });
  }

  DateTime _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

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
        return type.isEmpty ? 'غير محدد' : type;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'essay':
        return Icons.subject;
      case 'true_false':
        return Icons.rule;
      case 'single_choice':
        return Icons.radio_button_checked;
      case 'multiple_choice':
        return Icons.check_box;
      case 'ordering':
        return Icons.reorder;
      default:
        return Icons.help_outline;
    }
  }

  Color _typeColor(BuildContext context, String type) {
    final scheme = Theme.of(context).colorScheme;

    switch (type) {
      case 'essay':
        return scheme.primary;
      case 'true_false':
        return scheme.tertiary;
      case 'single_choice':
        return scheme.secondary;
      case 'multiple_choice':
        return scheme.primary;
      case 'ordering':
        return scheme.error;
      default:
        return scheme.outline;
    }
  }

  int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatScore(dynamic value) {
    final score = _readDouble(value);

    if (score == score.roundToDouble()) {
      return score.toInt().toString();
    }

    return score.toString();
  }

  String _formatDate(dynamic value) {
    final date = _readDate(value);

    if (date.millisecondsSinceEpoch == 0) {
      return 'غير محدد';
    }

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$day/$month/$year';
  }

  Set<String> get _availableSubjectIds {
    final ids = <String>{};

    for (final doc in _allQuestions) {
      final subjectId = doc.data()['subjectId']?.toString() ?? '';

      if (subjectId.isNotEmpty) {
        ids.add(subjectId);
      }
    }

    return ids;
  }

  int get _essayCount {
    return _allQuestions
        .where((doc) => doc.data()['type'] == 'essay')
        .length;
  }

  int get _objectiveCount {
    return _allQuestions
        .where((doc) {
          final type = doc.data()['type']?.toString() ?? '';
          return type != 'essay';
        })
        .length;
  }

  void _clearFilters() {
    _searchController.clear();

    setState(() {
      _selectedSubjectId = '';
      _selectedType = 'all';
      _selectedSort = 'newest';
    });

    _applyFilters();
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _selectedSubjectId.isNotEmpty ||
        _selectedType != 'all';
  }

  void _handleAddQuestion() {
    if (widget.onAddQuestion != null) {
      widget.onAddQuestion!();
      return;
    }

    _showMessage(
      'اربط زر إضافة السؤال بشاشة إضافة السؤال الحالية.',
    );
  }

  void _handleEditQuestion(
    String questionId,
    Map<String, dynamic> questionData,
  ) {
    if (widget.onEditQuestion != null) {
      widget.onEditQuestion!(
        questionId,
        questionData,
      );
      return;
    }

    _showMessage(
      'اربط تعديل السؤال بشاشة التعديل الحالية.',
    );
  }

  Future<void> _confirmDeleteQuestion(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final text = data['text']?.toString().trim() ?? '';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('حذف السؤال'),
            content: Text(
              text.isEmpty
                  ? 'هل تريد حذف هذا السؤال من بنك الأسئلة؟'
                  : 'هل تريد حذف السؤال التالي من بنك الأسئلة؟\n\n$text',
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
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    final teacherId = _auth.currentUser?.uid;

    if (teacherId == null) {
      _showMessage('لم يتم العثور على جلسة المعلم.');
      return;
    }

    try {
      // السؤال قد يكون مستخدمًا في اختبارات سابقة.
      // لذلك لا نحذفه مباشرة إذا كان مرتبطًا باختبار.
      final usageSnapshot = await _firestore
          .collection('quizQuestions')
          .where('questionId', isEqualTo: doc.id)
          .limit(1)
          .get();

      if (usageSnapshot.docs.isNotEmpty) {
        _showMessage(
          'لا يمكن حذف هذا السؤال لأنه مستخدم في اختبار. '
          'يمكنك تركه في بنك الأسئلة وعدم استخدامه في اختبارات جديدة.',
        );
        return;
      }

      final questionRef =
          _firestore.collection('questions').doc(doc.id);

      final keyRef =
          _firestore.collection('questionKeys').doc(doc.id);
      final unitRef =
          _firestore.collection('questionUnit').doc(doc.id);

      final batch = _firestore.batch();

      batch.delete(questionRef);
      batch.delete(keyRef);
      batch.delete(unitRef);

      await batch.commit();

      if (!mounted) {
        return;
      }

      setState(() {
        _allQuestions.removeWhere(
          (item) => item.id == doc.id,
        );
      });

      _applyFilters();

      _showMessage('تم حذف السؤال بنجاح.');
    } on FirebaseException catch (e) {
      _showMessage(
        'تعذر حذف السؤال: ${e.message ?? e.code}',
      );
    } catch (e) {
      _showMessage(
        'تعذر حذف السؤال: $e',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Widget _buildHeaderStats(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildStat(
              context,
              icon: Icons.library_books,
              title: 'كل الأسئلة',
              value: '${_allQuestions.length}',
            ),
            _buildStat(
              context,
              icon: Icons.check_circle_outline,
              title: 'موضوعية',
              value: '$_objectiveCount',
            ),
            _buildStat(
              context,
              icon: Icons.edit_note,
              title: 'مقالية',
              value: '$_essayCount',
            ),
            _buildStat(
              context,
              icon: Icons.filter_alt_outlined,
              title: 'المعروضة',
              value: '${_filteredQuestions.length}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(
        minWidth: 115,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final subjectIds = _availableSubjectIds.toList()
      ..sort((a, b) {
        final aName = _subjectNames[a] ?? a;
        final bName = _subjectNames[b] ?? b;
        return aName.compareTo(bName);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                labelText: 'بحث في نص السؤال',
                hintText: 'اكتب كلمة أو جزءًا من السؤال...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear),
                        tooltip: 'مسح البحث',
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;

                final subjectDropdown =
                    DropdownButtonFormField<String>(
                  value: _selectedSubjectId,
                  decoration: const InputDecoration(
                    labelText: 'المادة',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('كل المواد'),
                    ),
                    ...subjectIds.map(
                      (subjectId) {
                        return DropdownMenuItem<String>(
                          value: subjectId,
                          child: Text(
                            _subjectNames[subjectId] ?? subjectId,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSubjectId = value ?? '';
                    });
                    _applyFilters();
                  },
                );

                final typeDropdown =
                    DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'نوع السؤال',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('كل الأنواع'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'single_choice',
                      child: Text('اختيار من متعدد'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'multiple_choice',
                      child: Text('اختيار متعدد'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'true_false',
                      child: Text('صح / خطأ'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'ordering',
                      child: Text('ترتيب'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'essay',
                      child: Text('مقالي'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedType = value ?? 'all';
                    });
                    _applyFilters();
                  },
                );

                final sortDropdown =
                    DropdownButtonFormField<String>(
                  value: _selectedSort,
                  decoration: const InputDecoration(
                    labelText: 'الترتيب',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'newest',
                      child: Text('الأحدث أولًا'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'oldest',
                      child: Text('الأقدم أولًا'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'type',
                      child: Text('حسب النوع'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSort = value ?? 'newest';
                    });
                    _applyFilters();
                  },
                );

                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: subjectDropdown),
                      const SizedBox(width: 10),
                      Expanded(child: typeDropdown),
                      const SizedBox(width: 10),
                      Expanded(child: sortDropdown),
                    ],
                  );
                }

                return Column(
                  children: [
                    subjectDropdown,
                    const SizedBox(height: 10),
                    typeDropdown,
                    const SizedBox(height: 10),
                    sortDropdown,
                  ],
                );
              },
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('مسح الفلاتر'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    final text = data['text']?.toString().trim() ?? '';
    final type = data['type']?.toString() ?? '';
    final subjectId = data['subjectId']?.toString() ?? '';
    final score = _formatScore(data['score']);
    final timeLimit = _readInt(data['timeLimitSeconds']);

    final typeColor = _typeColor(context, type);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _handleEditQuestion(
          doc.id,
          Map<String, dynamic>.from(data),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor:
                        typeColor.withValues(alpha: 0.12),
                    foregroundColor: typeColor,
                    child: Icon(
                      _typeIcon(type),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text.isEmpty ? 'سؤال بدون نص' : text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _handleEditQuestion(
                          doc.id,
                          Map<String, dynamic>.from(data),
                        );
                      } else if (value == 'delete') {
                        _confirmDeleteQuestion(doc);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('تعديل'),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('حذف'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    context,
                    icon: _typeIcon(type),
                    label: _typeLabel(type),
                    color: typeColor,
                  ),
                  if (subjectId.isNotEmpty)
                    _buildInfoChip(
                      context,
                      icon: Icons.menu_book_outlined,
                      label: _subjectNames[subjectId] ?? subjectId,
                    ),
                  _buildInfoChip(
                    context,
                    icon: Icons.star_border,
                    label: 'الدرجة: $score',
                  ),
                  if (timeLimit > 0)
                    _buildInfoChip(
                      context,
                      icon: Icons.timer_outlined,
                      label: 'الوقت: $timeLimitث',
                    ),
                  _buildInfoChip(
                    context,
                    icon: Icons.calendar_today_outlined,
                    label: _formatDate(data['createdAt']),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final chipColor = color ?? scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: chipColor,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final hasFilters = _hasActiveFilters;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              hasFilters
                  ? Icons.search_off
                  : Icons.library_books_outlined,
              size: 54,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'لا توجد أسئلة مطابقة للفلاتر'
                  : 'بنك الأسئلة فارغ',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'جرّب تغيير البحث أو المادة أو نوع السؤال.'
                  : 'ابدأ بإضافة أسئلة إلى بنك الأسئلة، ثم استخدمها لاحقًا في أي اختبار.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('مسح الفلاتر'),
              ),
            ] else ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _handleAddQuestion,
                icon: const Icon(Icons.add),
                label: const Text('إضافة أول سؤال'),
              ),
            ],
          ],
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
                onPressed: _loadQuestionBank,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadQuestionBank,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeaderStats(context),
          const SizedBox(height: 12),
          _buildFilters(context),
          const SizedBox(height: 14),
          if (_filteredQuestions.isEmpty)
            _buildEmptyState(context)
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              child: Row(
                children: [
                  Text(
                    'الأسئلة',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${_filteredQuestions.length} سؤال',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ..._filteredQuestions.map(
              (doc) => _buildQuestionCard(
                context,
                doc,
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
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
            'بنك الأسئلة',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _loadQuestionBank,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _handleAddQuestion,
          icon: const Icon(Icons.add),
          label: const Text('إضافة سؤال'),
        ),
        body: SafeArea(
          child: _buildBody(context),
        ),
      ),
    );
  }
}
