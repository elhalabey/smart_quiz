import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AddQuestionScreen extends StatefulWidget {
  final String quizId;
  final String quizTitle;
  final Map<String, dynamic> quizData;

  const AddQuestionScreen({
    super.key,
    required this.quizId,
    required this.quizTitle,
    required this.quizData,
  });

  @override
  State<AddQuestionScreen> createState() =>
      _AddQuestionScreenState();
}

class _AddQuestionScreenState
    extends State<AddQuestionScreen> {
  final _formKey = GlobalKey<FormState>();

  final _textController = TextEditingController();
  final _scoreController =
      TextEditingController(text: '1');
  final _timeLimitController =
      TextEditingController(text: '0');
  final _maxCharactersController =
      TextEditingController(text: '0');
  final _modelAnswerController =
      TextEditingController();

  String _type = 'single_choice';

  final List<TextEditingController> _optionControllers = [];

  int _correctOption = 0;

  final Set<int> _correctOptions = {};

  List<int> _correctOrder = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _setDefaultOptions();
  }

  void _setDefaultOptions() {
    _optionControllers.clear();

    for (var i = 0; i < 4; i++) {
      _optionControllers.add(
        TextEditingController(),
      );
    }

    _correctOptions.clear();
    _correctOptions.add(0);

    _correctOrder = [0, 1, 2, 3];
  }

  @override
  void dispose() {
    _textController.dispose();
    _scoreController.dispose();
    _timeLimitController.dispose();
    _maxCharactersController.dispose();
    _modelAnswerController.dispose();

    for (final controller in _optionControllers) {
      controller.dispose();
    }

    super.dispose();
  }

   void _changeType(String? value) {
    if (value == null) {
      return;
    }

    setState(() {
      _type = value;

      if (_type == 'true_false') {
        for (final controller in _optionControllers) {
          controller.dispose();
        }

        _optionControllers.clear();

        _optionControllers.add(
          TextEditingController(text: 'صح'),
        );
        _optionControllers.add(
          TextEditingController(text: 'خطأ'),
        );

        _correctOption = 0;
        _correctOptions
          ..clear()
          ..add(0);

        _correctOrder = [0, 1];
      } else if (_type == 'essay') {
        for (final controller in _optionControllers) {
          controller.dispose();
        }

        _optionControllers.clear();

        _correctOption = 0;
        _correctOptions.clear();
        _correctOrder.clear();
      } else if (_optionControllers.isEmpty) {
        _setDefaultOptions();
      }
    });
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(
        TextEditingController(),
      );
      _correctOrder = List.generate(
        _optionControllers.length,
        (index) => index,
      );
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      return;
    }

    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);

      if (_correctOption >= _optionControllers.length) {
        _correctOption = 0;
      }

      _correctOptions.remove(index);

      final adjusted = <int>{};

      for (final value in _correctOptions) {
        if (value > index) {
          adjusted.add(value - 1);
        } else {
          adjusted.add(value);
        }
      }

      _correctOptions
        ..clear()
        ..addAll(adjusted);

      _correctOrder = List.generate(
        _optionControllers.length,
        (i) => i,
      );
    });
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final text = _textController.text.trim();

    if (text.isEmpty) {
      return;
    }

    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .toList();

    if (_type != 'essay') {
      if (options.any((option) => option.isEmpty)) {
        _showMessage('يجب كتابة جميع الاختيارات');
        return;
      }
    }

    if (_type == 'multiple_choice' &&
        _correctOptions.isEmpty) {
      _showMessage('اختر إجابة صحيحة واحدة على الأقل');
      return;
    }

    if (_type == 'single_choice' ||
        _type == 'true_false') {
      if (_correctOption < 0 ||
          _correctOption >= options.length) {
        _showMessage('حدد الإجابة الصحيحة');
        return;
      }
    }

    if (_type == 'ordering' &&
        _correctOrder.length != options.length) {
      _showMessage('تأكد من ترتيب الاختيارات');
      return;
    }

    final score =
        double.tryParse(_scoreController.text.trim()) ?? 0;

    final timeLimit =
        int.tryParse(_timeLimitController.text.trim()) ?? 0;

    final maxCharacters =
        int.tryParse(
              _maxCharactersController.text.trim(),
            ) ??
            0;

    setState(() {
      _saving = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      final questionRef =
          firestore.collection('questions').doc();

      final quizQuestionRef = firestore
          .collection('quizQuestions')
          .doc(
            '${widget.quizId}_${questionRef.id}',
          );

      final keyRef = firestore
          .collection('questionKeys')
          .doc(questionRef.id);

      final existingLinks = await firestore
          .collection('quizQuestions')
          .where(
            'quizId',
            isEqualTo: widget.quizId,
          )
          .get();

      var nextOrder = 1;

      for (final doc in existingLinks.docs) {
        final value =
            (doc.data()['order'] as num?)?.toInt() ?? 0;

        if (value >= nextOrder) {
          nextOrder = value + 1;
        }
      }

      final batch = firestore.batch();

      final teacherId =
          (widget.quizData['teacherId'] as String?) ?? '';

      final subjectId =
          (widget.quizData['subjectId'] as String?) ?? '';

      batch.set(questionRef, {
        'teacherId': teacherId,
        'subjectId': subjectId,
        'type': _type,
        'text': text,
        'options': _type == 'essay' ? [] : options,
        'score': score,
        'timeLimitSeconds': timeLimit,
        'maxCharacters':
            _type == 'essay' ? maxCharacters : 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(quizQuestionRef, {
        'quizId': widget.quizId,
        'questionId': questionRef.id,
        'order': nextOrder,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final keyData = <String, dynamic>{
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_type == 'single_choice' ||
          _type == 'true_false') {
        keyData['correctOption'] = _correctOption;
      }

      if (_type == 'multiple_choice') {
        keyData['correctOptions'] =
            (_correctOptions.toList()..sort());
      }

      if (_type == 'ordering') {
        keyData['correctOrder'] = _correctOrder;
      }

      if (_type == 'essay') {
        keyData['modelAnswer'] =
            _modelAnswerController.text.trim();
      }

      batch.set(keyRef, keyData);

      await batch.commit();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إضافة السؤال بنجاح'),
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'حدث خطأ أثناء إضافة السؤال:\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
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

  Widget _buildOptionsSection() {
    if (_type == 'essay') {
      return TextFormField(
        controller: _modelAnswerController,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'الإجابة النموذجية',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'الاختيارات',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(
          _optionControllers.length,
          (index) {
            final controller =
                _optionControllers[index];

            return Padding(
              padding:
                  const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  if (_type == 'multiple_choice')
                    Checkbox(
                      value:
                          _correctOptions.contains(index),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _correctOptions.add(index);
                          } else {
                            _correctOptions.remove(index);
                          }
                        });
                      },
                    )
                  else if (_type == 'ordering')
                    CircleAvatar(
                      radius: 18,
                      child: Text('${index + 1}'),
                    )
                  else
                    Radio<int>(
                      value: index,
                      groupValue: _correctOption,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _correctOption = value;
                        });
                      },
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText:
                            'الاختيار ${index + 1}',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (_type == 'essay') {
                          return null;
                        }

                        if (value == null ||
                            value.trim().isEmpty) {
                          return 'مطلوب';
                        }

                        return null;
                      },
                    ),
                  ),
                  if (_type != 'true_false')
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                      ),
                      onPressed: () {
                        _removeOption(index);
                      },
                    ),
                ],
              ),
            );
          },
        ),
        if (_type != 'true_false')
          OutlinedButton.icon(
            onPressed: _addOption,
            icon: const Icon(Icons.add),
            label: const Text('إضافة اختيار'),
          ),
        if (_type == 'ordering')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'في سؤال الترتيب، ترتيب الاختيارات الحالي هو الإجابة الصحيحة.',
              style: TextStyle(fontSize: 12),
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
            'إضافة سؤال',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.quizTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _textController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'نص السؤال',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return 'اكتب نص السؤال';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'نوع السؤال',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'essay',
                    child: Text('مقالي'),
                  ),
                  DropdownMenuItem(
                    value: 'true_false',
                    child: Text('صح / خطأ'),
                  ),
                  DropdownMenuItem(
                    value: 'single_choice',
                    child: Text('اختيار من متعدد'),
                  ),
                  DropdownMenuItem(
                    value: 'multiple_choice',
                    child: Text('اختيار متعدد'),
                  ),
                  DropdownMenuItem(
                    value: 'ordering',
                    child: Text('ترتيب'),
                  ),
                ],
                onChanged: _changeType,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _scoreController,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'الدرجة',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (double.tryParse(
                              value?.trim() ?? '',
                            ) ==
                            null) {
                          return 'أدخل درجة صحيحة';
                        }

                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _timeLimitController,
                      keyboardType:
                          TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الوقت بالثواني',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_type == 'essay')
                TextFormField(
                  controller: _maxCharactersController,
                  keyboardType:
                      TextInputType.number,
                  decoration: const InputDecoration(
                    labelText:
                        'الحد الأقصى لعدد الحروف',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (_type == 'essay')
                const SizedBox(height: 16),
              _buildOptionsSection(),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : _saveQuestion,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _saving
                      ? 'جاري الحفظ...'
                      : 'حفظ السؤال',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
