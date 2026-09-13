import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';

class EditTeacherQuestionScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final String questionId;
  final String quizId;
  final String quizTitle;
  final String subjectId;
  final Map<String, dynamic> questionData;

  const EditTeacherQuestionScreen({
    super.key,
    required this.sessionManager,
    required this.questionId,
    required this.quizId,
    required this.quizTitle,
    required this.subjectId,
    required this.questionData,
  });

  @override
  State<EditTeacherQuestionScreen> createState() =>
      _EditTeacherQuestionScreenState();
}

class _EditTeacherQuestionScreenState
    extends State<EditTeacherQuestionScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final TextEditingController _textController =
      TextEditingController();

  final TextEditingController _scoreController =
      TextEditingController();

  final TextEditingController _timeLimitController =
      TextEditingController();

  final TextEditingController _modelAnswerController =
      TextEditingController();

  final TextEditingController _maxCharactersController =
      TextEditingController();

  final List<TextEditingController> _optionControllers =
      [];

  String? _selectedType;

  final Set<int> _selectedCorrectOptions =
      <int>{};

  List<int> _correctOrder = <int>[];

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadQuestion();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scoreController.dispose();
    _timeLimitController.dispose();
    _modelAnswerController.dispose();
    _maxCharactersController.dispose();

    for (final controller in _optionControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  Future<void> _loadQuestion() async {
    try {
      final questionSnapshot = await _firestore
          .collection('questions')
          .doc(widget.questionId)
          .get();

      if (!questionSnapshot.exists) {
        throw Exception(
          'السؤال غير موجود.',
        );
      }

      final questionData =
          questionSnapshot.data();

      if (questionData == null) {
        throw Exception(
          'تعذر قراءة بيانات السؤال.',
        );
      }

      final keySnapshot = await _firestore
          .collection('questionKeys')
          .doc(widget.questionId)
          .get();

      final keyData =
          keySnapshot.data() ??
              <String, dynamic>{};

      final type =
          questionData['type']?.toString();

      _textController.text =
          questionData['text']?.toString() ?? '';

      _scoreController.text =
          _readNumberAsString(
        questionData['score'],
        fallback: '1',
      );

      _timeLimitController.text =
          _readNumberAsString(
        questionData['timeLimitSeconds'],
        fallback: '0',
      );

      _modelAnswerController.text =
          keyData['modelAnswer']?.toString() ?? '';

      _maxCharactersController.text =
          _readNumberAsString(
        questionData['maxCharacters'],
        fallback: '0',
      );

      _selectedType = type;

      final options =
          _readOptions(questionData['options']);

      _clearOptionControllers();

      for (final option in options) {
        _optionControllers.add(
          TextEditingController(
            text: option,
          ),
        );
      }

      _loadCorrectAnswers(
        type: type,
        keyData: keyData,
        optionCount: options.length,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      _showMessage(
        'حدث خطأ أثناء تحميل السؤال:\n$error',
      );
    }
  }

  String _readNumberAsString(
    dynamic value, {
    required String fallback,
  }) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toString();
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return fallback;
    }

    return text;
  }

  List<String> _readOptions(dynamic value) {
    if (value is List) {
      return value
          .map(
            (item) => item?.toString() ?? '',
          )
          .toList();
    }

    return <String>[];
  }

  void _loadCorrectAnswers({
    required String? type,
    required Map<String, dynamic> keyData,
    required int optionCount,
  }) {
    _selectedCorrectOptions.clear();
    _correctOrder = <int>[];

    if (type == 'single_choice') {
      final correctOption =
          _readInt(keyData['correctOption']);

      if (correctOption != null &&
          correctOption >= 0 &&
          correctOption < optionCount) {
        _selectedCorrectOptions.add(
          correctOption,
        );
      }

      return;
    }

    if (type == 'multiple_choice') {
      final correctOptions =
          keyData['correctOptions'];

      if (correctOptions is List) {
        for (final value in correctOptions) {
          final index = _readInt(value);

          if (index != null &&
              index >= 0 &&
              index < optionCount) {
            _selectedCorrectOptions.add(
              index,
            );
          }
        }
      }

      return;
    }

    if (type == 'ordering') {
      final correctOrder =
          keyData['correctOrder'];

      if (correctOrder is List) {
        for (final value in correctOrder) {
          final index = _readInt(value);

          if (index != null &&
              index >= 0 &&
              index < optionCount) {
            _correctOrder.add(index);
          }
        }
      }

      if (_correctOrder.isEmpty &&
          optionCount > 0) {
        _correctOrder =
            List<int>.generate(
          optionCount,
          (index) => index,
        );
      }
    }
  }

  int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    );
  }

  void _clearOptionControllers() {
    for (final controller in _optionControllers) {
      controller.dispose();
    }

    _optionControllers.clear();
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(
        TextEditingController(),
      );

      if (_selectedType == 'ordering') {
        _correctOrder.add(
          _optionControllers.length - 1,
        );
      }
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      _showMessage(
        'يجب أن يحتوي السؤال على خيارين على الأقل.',
      );
      return;
    }

    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);

      final updatedCorrect =
          <int>{};

      for (final value in _selectedCorrectOptions) {
        if (value == index) {
          continue;
        }

        if (value > index) {
          updatedCorrect.add(value - 1);
        } else {
          updatedCorrect.add(value);
        }
      }

      _selectedCorrectOptions
        ..clear()
        ..addAll(updatedCorrect);

      if (_selectedType == 'ordering') {
        final updatedOrder =
            <int>[];

        for (final value in _correctOrder) {
          if (value == index) {
            continue;
          }

          if (value > index) {
            updatedOrder.add(value - 1);
          } else {
            updatedOrder.add(value);
          }
        }

        _correctOrder = updatedOrder;
      }
    });
  }

  void _toggleCorrectOption(int index) {
    if (_selectedType == 'single_choice') {
      setState(() {
        _selectedCorrectOptions
          ..clear()
          ..add(index);
      });

      return;
    }

    setState(() {
      if (_selectedCorrectOptions.contains(index)) {
        _selectedCorrectOptions.remove(index);
      } else {
        _selectedCorrectOptions.add(index);
      }
    });
  }

  void _moveOrderingOption(
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    setState(() {
      final item =
          _correctOrder.removeAt(oldIndex);

      _correctOrder.insert(
        newIndex,
        item,
      );
    });
  }

  String _typeLabel(String type) {
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

  Future<bool> _validateTeacherAccess() async {
    final teacherId =
        widget.sessionManager.currentSession?.uid;

    if (teacherId == null ||
        teacherId.isEmpty) {
      _showMessage(
        'لم يتم العثور على حساب المعلم.',
      );
      return false;
    }

    final questionSnapshot = await _firestore
        .collection('questions')
        .doc(widget.questionId)
        .get();

    if (!questionSnapshot.exists) {
      _showMessage(
        'السؤال غير موجود.',
      );
      return false;
    }

    final questionData =
        questionSnapshot.data();

    if (questionData == null) {
      _showMessage(
        'تعذر قراءة بيانات السؤال.',
      );
      return false;
    }

    if (questionData['teacherId']
            ?.toString() !=
        teacherId) {
      _showMessage(
        'لا يمكنك تعديل هذا السؤال.',
      );
      return false;
    }

    final subjectId =
        questionData['subjectId']?.toString();

    if (subjectId == null ||
        subjectId.isEmpty) {
      _showMessage(
        'السؤال غير مرتبط بمادة.',
      );
      return false;
    }

    final teacherSubjectSnapshot =
        await _firestore
            .collection('teacherSubjects')
            .doc(
              '${teacherId}_$subjectId',
            )
            .get();

    if (!teacherSubjectSnapshot.exists) {
      _showMessage(
        'أنت غير مُكلّف بتدريس هذه المادة.',
      );
      return false;
    }

    return true;
  }

  bool _validateOptions() {
    if (_selectedType == 'true_false' ||
        _selectedType == 'essay') {
      return true;
    }

    if (_optionControllers.length < 2) {
      _showMessage(
        'يجب إضافة خيارين على الأقل.',
      );
      return false;
    }

    for (var index = 0;
        index < _optionControllers.length;
        index++) {
      if (_optionControllers[index]
          .text
          .trim()
          .isEmpty) {
        _showMessage(
          'يرجى كتابة جميع الاختيارات.',
        );
        return false;
      }
    }

    if (_selectedType == 'single_choice') {
      if (_selectedCorrectOptions.length != 1) {
        _showMessage(
          'يرجى تحديد إجابة صحيحة واحدة.',
        );
        return false;
      }
    }

    if (_selectedType == 'multiple_choice') {
      if (_selectedCorrectOptions.isEmpty) {
        _showMessage(
          'يرجى تحديد إجابة صحيحة واحدة على الأقل.',
        );
        return false;
      }
    }

    if (_selectedType == 'ordering') {
      if (_correctOrder.length !=
          _optionControllers.length) {
        _showMessage(
          'يرجى ترتيب جميع الاختيارات.',
        );
        return false;
      }
    }

    return true;
  }

  int? _readRequiredInt(
    String value,
    String fieldName,
  ) {
    final parsed =
        int.tryParse(value.trim());

    if (parsed == null) {
      _showMessage(
        'يرجى إدخال $fieldName بشكل صحيح.',
      );
      return null;
    }

    return parsed;
  }

  Future<void> _saveQuestion() async {
    if (_saving) {
      return;
    }

    final text =
        _textController.text.trim();

    if (text.isEmpty) {
      _showMessage(
        'يرجى كتابة نص السؤال.',
      );
      return;
    }

    final type = _selectedType;

    if (type == null ||
        type.isEmpty) {
      _showMessage(
        'نوع السؤال غير محدد.',
      );
      return;
    }

    if (!_validateOptions()) {
      return;
    }

    final score = _readRequiredInt(
      _scoreController.text,
      'الدرجة',
    );

    if (score == null ||
        score <= 0) {
      _showMessage(
        'الدرجة يجب أن تكون أكبر من صفر.',
      );
      return;
    }

    final timeLimit = _readRequiredInt(
      _timeLimitController.text,
      'الوقت',
    );

    if (timeLimit == null ||
        timeLimit < 0) {
      _showMessage(
        'الوقت لا يمكن أن يكون رقمًا سالبًا.',
      );
      return;
    }

    var maxCharacters = 0;

    if (type == 'essay') {
      maxCharacters = _readRequiredInt(
            _maxCharactersController.text,
            'الحد الأقصى لعدد الحروف',
          ) ??
          0;

      if (maxCharacters < 0) {
        _showMessage(
          'الحد الأقصى لعدد الحروف لا يمكن أن يكون سالبًا.',
        );
        return;
      }
    }

    final teacherId =
        widget.sessionManager.currentSession?.uid;

    if (teacherId == null ||
        teacherId.isEmpty) {
      _showMessage(
        'لم يتم العثور على حساب المعلم.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final hasAccess =
          await _validateTeacherAccess();

      if (!hasAccess) {
        return;
      }

      final questionRef = _firestore
          .collection('questions')
          .doc(widget.questionId);

      final keyRef = _firestore
          .collection('questionKeys')
          .doc(widget.questionId);

      final options =
          _optionControllers
              .map(
                (controller) =>
                    controller.text.trim(),
              )
              .toList();

      final questionData =
          <String, dynamic>{
        'teacherId': teacherId,
        'subjectId': widget.subjectId,
        'type': type,
        'text': text,
        'options': options,
        'score': score,
        'timeLimitSeconds': timeLimit,
        'maxCharacters':
            type == 'essay'
                ? maxCharacters
                : 0,
        'updatedAt':
            FieldValue.serverTimestamp(),
      };

      final keyData =
          <String, dynamic>{
        'updatedAt':
            FieldValue.serverTimestamp(),
      };

      if (type == 'single_choice') {
        keyData['correctOption'] =
            _selectedCorrectOptions.first;
        keyData['correctOptions'] =
            FieldValue.delete();
        keyData['correctOrder'] =
            FieldValue.delete();
        keyData['modelAnswer'] =
            FieldValue.delete();
      } else if (type == 'multiple_choice') {
        final correctOptions =
            _selectedCorrectOptions.toList()
              ..sort();

        keyData['correctOptions'] =
            correctOptions;
        keyData['correctOption'] =
            FieldValue.delete();
        keyData['correctOrder'] =
            FieldValue.delete();
        keyData['modelAnswer'] =
            FieldValue.delete();
      } else if (type == 'ordering') {
        keyData['correctOrder'] =
            List<int>.from(_correctOrder);
        keyData['correctOption'] =
            FieldValue.delete();
        keyData['correctOptions'] =
            FieldValue.delete();
        keyData['modelAnswer'] =
            FieldValue.delete();
      } else if (type == 'essay') {
        keyData['modelAnswer'] =
            _modelAnswerController.text.trim();
        keyData['correctOption'] =
            FieldValue.delete();
        keyData['correctOptions'] =
            FieldValue.delete();
        keyData['correctOrder'] =
            FieldValue.delete();
      } else if (type == 'true_false') {
        keyData['correctOption'] =
            _selectedCorrectOptions.isEmpty
                ? null
                : _selectedCorrectOptions.first;
        keyData['correctOptions'] =
            FieldValue.delete();
        keyData['correctOrder'] =
            FieldValue.delete();
        keyData['modelAnswer'] =
            FieldValue.delete();
      }

      final batch =
          _firestore.batch();

      batch.update(
        questionRef,
        questionData,
      );

      batch.update(
        keyRef,
        keyData,
      );

      await batch.commit();

      if (!mounted) {
        return;
      }

      _showMessage(
        'تم تحديث السؤال بنجاح',
      );

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'حدث خطأ أثناء تحديث السؤال:\n$error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _buildOptionsSection() {
    if (_selectedType == 'true_false') {
      return _buildTrueFalseSection();
    }

    if (_selectedType == 'essay') {
      return _buildEssaySection();
    }

    if (_selectedType == 'ordering') {
      return _buildOrderingSection();
    }

    return _buildChoiceSection();
  }

  Widget _buildChoiceSection() {
    final isMultiple =
        _selectedType == 'multiple_choice';

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          isMultiple
              ? 'الاختيارات والإجابات الصحيحة'
              : 'الاختيارات والإجابة الصحيحة',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isMultiple
              ? 'حدد كل الاختيارات الصحيحة.'
              : 'حدد الاختيار الصحيح.',
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(
          _optionControllers.length,
          (index) {
            final controller =
                _optionControllers[index];

            final selected =
                _selectedCorrectOptions
                    .contains(index);

            return Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 12,
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration:
                          InputDecoration(
                        labelText:
                            'الاختيار ${index + 1}',
                        border:
                            const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      Checkbox(
                        value: selected,
                        onChanged:
                            (_) =>
                                _toggleCorrectOption(
                          index,
                        ),
                      ),
                      const Text(
                        'صحيح',
                        style: TextStyle(
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip:
                        'حذف الاختيار',
                    onPressed:
                        _optionControllers
                                    .length >
                                2
                            ? () =>
                                _removeOption(
                                  index,
                                )
                            : null,
                    icon: const Icon(
                      Icons
                          .delete_outline,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        OutlinedButton.icon(
          onPressed:
              _addOption,
          icon: const Icon(
            Icons.add,
          ),
          label: const Text(
            'إضافة اختيار',
          ),
        ),
      ],
    );
  }

  Widget _buildTrueFalseSection() {
    final selected =
        _selectedCorrectOptions.isEmpty
            ? null
            : _selectedCorrectOptions.first;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'الإجابة الصحيحة',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        RadioListTile<int>(
          value: 0,
          groupValue: selected,
          onChanged: (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _selectedCorrectOptions
                ..clear()
                ..add(value);
            });
          },
          title: const Text(
            'صح',
          ),
        ),
        RadioListTile<int>(
          value: 1,
          groupValue: selected,
          onChanged: (value) {
            if (value == null) {
              return;
            }

            setState(() {
              _selectedCorrectOptions
                ..clear()
                ..add(value);
            });
          },
          title: const Text(
            'خطأ',
          ),
        ),
      ],
    );
  }

  Widget _buildEssaySection() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'إعدادات السؤال المقالي',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller:
              _modelAnswerController,
          maxLines: 5,
          decoration:
              const InputDecoration(
            labelText:
                'الإجابة النموذجية',
            hintText:
                'اكتب الإجابة النموذجية المستخدمة في التصحيح اليدوي.',
            border:
                OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller:
              _maxCharactersController,
          keyboardType:
              TextInputType.number,
          decoration:
              const InputDecoration(
            labelText:
                'الحد الأقصى لعدد الحروف',
            hintText:
                '0 = بدون حد',
            border:
                OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderingSection() {
    if (_correctOrder.length !=
        _optionControllers.length) {
      _correctOrder =
          List<int>.generate(
        _optionControllers.length,
        (index) => index,
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'الترتيب الصحيح',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'اسحب الاختيارات لترتيبها بالترتيب الصحيح.',
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount:
              _correctOrder.length,
          onReorder:
              _moveOrderingOption,
          itemBuilder:
              (context, index) {
            final optionIndex =
                _correctOrder[index];

            final controller =
                _optionControllers[
                    optionIndex];

            return Card(
              key: ValueKey(
                'ordering_$optionIndex',
              ),
              margin:
                  const EdgeInsets.only(
                bottom: 8,
              ),
              child: ListTile(
                leading:
                    CircleAvatar(
                  child: Text(
                    '${index + 1}',
                  ),
                ),
                title:
                    TextField(
                  controller:
                      controller,
                  decoration:
                      InputDecoration(
                    labelText:
                        'الاختيار ${optionIndex + 1}',
                    border:
                        const OutlineInputBorder(),
                  ),
                ),
                trailing:
                    const Icon(
                  Icons
                      .drag_handle,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              _addOption,
          icon: const Icon(
            Icons.add,
          ),
          label: const Text(
            'إضافة اختيار',
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionSettings() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'إعدادات السؤال',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller:
                    _scoreController,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText:
                      'الدرجة',
                  border:
                      OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller:
                    _timeLimitController,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText:
                      'الوقت بالثواني',
                  hintText:
                      '0 = بدون حد',
                  border:
                      OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        120,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            widget.quizTitle,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'تعديل السؤال',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'نوع السؤال: ${_typeLabel(_selectedType ?? '')}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller:
                _textController,
            maxLines: 5,
            decoration:
                const InputDecoration(
              labelText:
                  'نص السؤال',
              border:
                  OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          _buildOptionsSection(),
          const SizedBox(height: 28),
          _buildQuestionSettings(),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
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
            'تعديل السؤال',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(),
              )
            : _buildBody(),
        bottomNavigationBar:
            _loading
                ? null
                : SafeArea(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        16,
                      ),
                      child: FilledButton.icon(
                        onPressed:
                            _saving
                                ? null
                                : _saveQuestion,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.save,
                              ),
                        label: Text(
                          _saving
                              ? 'جارٍ الحفظ...'
                              : 'حفظ التعديلات',
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}
