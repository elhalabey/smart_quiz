import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditQuestionScreen extends StatefulWidget {
  final String quizId;
  final String quizTitle;
  final String questionId;
  final Map<String, dynamic> questionData;
  final Map<String, dynamic> linkData;

  const EditQuestionScreen({
    super.key,
    required this.quizId,
    required this.quizTitle,
    required this.questionId,
    required this.questionData,
    required this.linkData,
  });

  @override
  State<EditQuestionScreen> createState() =>
      _EditQuestionScreenState();
}

class _EditQuestionScreenState
    extends State<EditQuestionScreen> {
  final _formKey = GlobalKey<FormState>();

  final _textController = TextEditingController();
  final _scoreController = TextEditingController();
  final _timeLimitController = TextEditingController();
  final _maxCharactersController = TextEditingController();
  final _modelAnswerController = TextEditingController();

  String _type = 'single_choice';

  final List<TextEditingController> _optionControllers = [];

  int _correctOption = 0;

  final Set<int> _correctOptions = {};

  List<int> _correctOrder = [];

  int _order = 1;

  bool _saving = false;

  bool _loadingKey = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadQuestionKey();
  }

  void _loadData() {
    final data = widget.questionData;

    _textController.text =
        (data['text'] as String?) ?? '';

    _type =
        (data['type'] as String?) ?? 'single_choice';

    _scoreController.text =
        ((data['score'] as num?) ?? 1).toString();

    _timeLimitController.text =
        ((data['timeLimitSeconds'] as num?) ?? 0)
            .toString();

    _maxCharactersController.text =
        ((data['maxCharacters'] as num?) ?? 0)
            .toString();

    _order =
        ((widget.linkData['order'] as num?) ?? 1)
            .toInt();

    final options =
        (data['options'] as List<dynamic>?) ?? [];

    for (final option in options) {
      _optionControllers.add(
        TextEditingController(
          text: option.toString(),
        ),
      );
    }

    if (_type == 'true_false' &&
        _optionControllers.isEmpty) {
      _optionControllers.add(
        TextEditingController(text: 'صح'),
      );
      _optionControllers.add(
        TextEditingController(text: 'خطأ'),
      );
    }

    if (_type == 'ordering' &&
        _optionControllers.isNotEmpty) {
      _correctOrder = List.generate(
        _optionControllers.length,
        (index) => index,
      );
    }
  }

  Future<void> _loadQuestionKey() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('questionKeys')
          .doc(widget.questionId)
          .get();

      if (!mounted) {
        return;
      }

      if (!doc.exists) {
        setState(() {
          _loadingKey = false;
        });
        return;
      }

      final data = doc.data() ?? {};

      setState(() {
        if (data['correctOption'] != null) {
          _correctOption =
              (data['correctOption'] as num).toInt();
        }

        _correctOptions.clear();

        final correctOptions =
            data['correctOptions'] as List<dynamic>?;

        if (correctOptions != null) {
          _correctOptions.addAll(
            correctOptions.map(
              (value) => (value as num).toInt(),
            ),
          );
        }

        final correctOrder =
            data['correctOrder'] as List<dynamic>?;

        if (correctOrder != null) {
          _correctOrder = correctOrder
              .map(
                (value) => (value as num).toInt(),
              )
              .toList();
        }

        if (data['modelAnswer'] != null) {
          _modelAnswerController.text =
              data['modelAnswer'].toString();
        }

        _loadingKey = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingKey = false;
      });

      _showMessage(
        'تعذر تحميل الإجابة الصحيحة:\n$e',
      );
    }
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

  void _addOption() {
    setState(() {
      _optionControllers.add(
        TextEditingController(),
      );

      if (_type == 'ordering') {
        _correctOrder = List.generate(
          _optionControllers.length,
          (index) => index,
        );
      }
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      return;
    }

    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);

      if (_correctOption >=
          _optionControllers.length) {
        _correctOption = 0;
      }

      final adjusted = <int>{};

      for (final value in _correctOptions) {
        if (value == index) {
          continue;
        }

        if (value > index) {
          adjusted.add(value - 1);
        } else {
          adjusted.add(value);
        }
      }

      _correctOptions
        ..clear()
        ..addAll(adjusted);

      if (_type == 'ordering') {
        _correctOrder = List.generate(
          _optionControllers.length,
          (i) => i,
        );
      } else {
        _correctOrder = [];
      }
    });
  }

  void _changeQuestionType(String value) {
    if (value == _type) {
      return;
    }

    setState(() {
      _type = value;

      if (_type == 'true_false') {
        for (final controller in _optionControllers) {
          controller.dispose();
        }

        _optionControllers
          ..clear()
          ..add(
            TextEditingController(text: 'صح'),
          )
          ..add(
            TextEditingController(text: 'خطأ'),
          );

        _correctOption = 0;
        _correctOptions.clear();
        _correctOrder = [];
      } else if (_type == 'ordering') {
        _correctOptions.clear();

        if (_optionControllers.isEmpty) {
          _optionControllers.add(
            TextEditingController(),
          );
          _optionControllers.add(
            TextEditingController(),
          );
        }

        _correctOrder = List.generate(
          _optionControllers.length,
          (index) => index,
        );

        _correctOption = 0;
      } else if (_type == 'multiple_choice') {
        _correctOption = 0;
        _correctOrder = [];

        if (_correctOptions.isEmpty &&
            _optionControllers.isNotEmpty) {
          _correctOptions.add(0);
        }
      } else if (_type == 'single_choice') {
        _correctOptions.clear();
        _correctOrder = [];
        _correctOption = 0;

        if (_optionControllers.isEmpty) {
          _optionControllers.add(
            TextEditingController(),
          );
          _optionControllers.add(
            TextEditingController(),
          );
        }
      } else if (_type == 'essay') {
        _correctOption = 0;
        _correctOptions.clear();
        _correctOrder = [];
      }
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
        .map(
          (controller) => controller.text.trim(),
        )
        .toList();

    if (_type != 'essay' &&
        options.any(
          (option) => option.isEmpty,
        )) {
      _showMessage('يجب كتابة جميع الاختيارات');
      return;
    }

    if (_type == 'multiple_choice' &&
        _correctOptions.isEmpty) {
      _showMessage(
        'اختر إجابة صحيحة واحدة على الأقل',
      );
      return;
    }

    if ((_type == 'single_choice' ||
            _type == 'true_false') &&
        (_correctOption < 0 ||
            _correctOption >= options.length)) {
      _showMessage(
        'اختر إجابة صحيحة',
      );
      return;
    }

    if (_type == 'ordering' &&
        _correctOrder.length != options.length) {
      _showMessage(
        'يجب تحديد ترتيب جميع الاختيارات',
      );
      return;
    }

    final score =
        double.tryParse(
              _scoreController.text.trim(),
            ) ??
            0;

    final timeLimit =
        int.tryParse(
              _timeLimitController.text.trim(),
            ) ??
            0;

    final maxCharacters =
        int.tryParse(
              _maxCharactersController.text.trim(),
            ) ??
            0;

    setState(() {
      _saving = true;
    });

    try {
      final firestore =
          FirebaseFirestore.instance;

      final questionRef = firestore
          .collection('questions')
          .doc(widget.questionId);

      final keyRef = firestore
          .collection('questionKeys')
          .doc(widget.questionId);

      final quizQuestionRef = firestore
          .collection('quizQuestions')
          .doc(
            '${widget.quizId}_${widget.questionId}',
          );

      final batch = firestore.batch();

      batch.update(
        questionRef,
        {
          'type': _type,
          'text': text,
          'options':
              _type == 'essay' ? [] : options,
          'score': score,
          'timeLimitSeconds': timeLimit,
          'maxCharacters':
              _type == 'essay'
                  ? maxCharacters
                  : 0,
          'updatedAt':
              FieldValue.serverTimestamp(),
        },
      );

      batch.set(
        quizQuestionRef,
        {
          'quizId': widget.quizId,
          'questionId': widget.questionId,
          'order': _order,
          'createdAt':
              widget.linkData['createdAt'] ??
                  FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final keyData =
          <String, dynamic>{
        'updatedAt':
            FieldValue.serverTimestamp(),
      };

      if (_type == 'single_choice' ||
          _type == 'true_false') {
        keyData['correctOption'] =
            _correctOption;
      } else {
        keyData['correctOption'] =
            FieldValue.delete();
      }

      if (_type == 'multiple_choice') {
        final sortedCorrectOptions =
            _correctOptions.toList()..sort();

        keyData['correctOptions'] =
            sortedCorrectOptions;
      } else {
        keyData['correctOptions'] =
            FieldValue.delete();
      }

      if (_type == 'ordering') {
        keyData['correctOrder'] =
            List<int>.from(_correctOrder);
      } else {
        keyData['correctOrder'] =
            FieldValue.delete();
      }

      if (_type == 'essay') {
        keyData['modelAnswer'] =
            _modelAnswerController.text.trim();
      } else {
        keyData['modelAnswer'] =
            FieldValue.delete();
      }

      batch.set(
        keyRef,
        keyData,
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تعديل السؤال بنجاح',
          ),
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'حدث خطأ أثناء تعديل السؤال:\n$e',
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
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
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
            return Padding(
              padding:
                  const EdgeInsets.only(
                bottom: 10,
              ),
              child: Row(
                children: [
                  if (_type == 'multiple_choice')
                    Checkbox(
                      value:
                          _correctOptions
                              .contains(index),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _correctOptions
                                .add(index);
                          } else {
                            _correctOptions
                                .remove(index);
                          }
                        });
                      },
                    )
                  else if (_type == 'ordering')
                    CircleAvatar(
                      radius: 18,
                      child: Text(
                        '${index + 1}',
                      ),
                    )
                  else
                    Radio<int>(
                      value: index,
                      groupValue:
                          _correctOption,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _correctOption =
                              value;
                        });
                      },
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller:
                          _optionControllers[
                              index],
                      decoration:
                          InputDecoration(
                        labelText:
                            'الاختيار ${index + 1}',
                        border:
                            const OutlineInputBorder(),
                      ),
                      validator: (value) {
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
                        Icons
                            .remove_circle_outline,
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
            label: const Text(
              'إضافة اختيار',
            ),
          ),
        if (_type == 'ordering')
          const Padding(
            padding:
                EdgeInsets.only(top: 8),
            child: Text(
              'ترتيب الاختيارات الظاهر هنا يمثل ترتيب الإجابة الصحيحة.',
              style: TextStyle(
                fontSize: 12,
              ),
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
            'تعديل السؤال',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: _loadingKey
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding:
                      const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.quizTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller:
                          _textController,
                      maxLines: 4,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'نص السؤال',
                        border:
                            OutlineInputBorder(),
                        alignLabelWithHint:
                            true,
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
                      isExpanded: true,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'نوع السؤال',
                        border:
                            OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'essay',
                          child: Text('مقالي'),
                        ),
                        DropdownMenuItem(
                          value: 'true_false',
                          child: Text(
                            'صح / خطأ',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'single_choice',
                          child: Text(
                            'اختيار من متعدد',
                          ),
                        ),
                        DropdownMenuItem(
                          value:
                              'multiple_choice',
                          child: Text(
                            'اختيار متعدد',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'ordering',
                          child: Text(
                            'ترتيب',
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        _changeQuestionType(
                          value,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child:
                              TextFormField(
                            controller:
                                _scoreController,
                            keyboardType:
                                const TextInputType
                                    .numberWithOptions(
                              decimal: true,
                            ),
                            decoration:
                                const InputDecoration(
                              labelText:
                                  'الدرجة',
                              border:
                                  OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Expanded(
                          child:
                              TextFormField(
                            controller:
                                _timeLimitController,
                            keyboardType:
                                TextInputType
                                    .number,
                            decoration:
                                const InputDecoration(
                              labelText:
                                  'الوقت بالثواني',
                              border:
                                  OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_type == 'essay')
                      TextFormField(
                        controller:
                            _maxCharactersController,
                        keyboardType:
                            TextInputType
                                .number,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'الحد الأقصى لعدد الحروف',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),
                    if (_type == 'essay')
                      const SizedBox(
                        height: 16,
                      ),
                    _buildOptionsSection(),
                    const SizedBox(
                      height: 24,
                    ),
                    FilledButton.icon(
                      onPressed:
                          _saving
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
                          : const Icon(
                              Icons.save,
                            ),
                      label: Text(
                        _saving
                            ? 'جاري الحفظ...'
                            : 'حفظ التعديل',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
