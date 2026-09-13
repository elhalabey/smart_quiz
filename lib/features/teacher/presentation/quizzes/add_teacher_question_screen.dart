import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/session/session_manager.dart';

class AddTeacherQuestionScreen extends StatefulWidget {
  final SessionManager sessionManager;
  final String subjectId;

  // Compatibility parameters kept temporarily because the old
  // TeacherQuestionsScreen still passes them. They are not used when
  // saving a question to the reusable question bank.
  final String? quizId;
  final String? quizTitle;

  const AddTeacherQuestionScreen({
    super.key,
    required this.sessionManager,
    required this.subjectId,
    this.quizId,
    this.quizTitle,
  });

  @override
  State<AddTeacherQuestionScreen> createState() =>
      _AddTeacherQuestionScreenState();
}

class _AddTeacherQuestionScreenState
    extends State<AddTeacherQuestionScreen> {
  final _formKey = GlobalKey<FormState>();

  final _questionController = TextEditingController();
  final _modelAnswerController = TextEditingController();

  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  String _questionType = 'single_choice';

  int? _correctOption;

  final List<int> _correctOptions = [];

  final List<int> _correctOrder = [0, 1, 2, 3];

  final _scoreController = TextEditingController(text: '1');
  final _timeLimitController = TextEditingController();

  int? _maxCharacters;

  bool _saving = false;

  @override
  void dispose() {
    _questionController.dispose();
    _modelAnswerController.dispose();
    _scoreController.dispose();
    _timeLimitController.dispose();

    for (final controller in _optionControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  bool get _needsOptions {
    return _questionType == 'single_choice' ||
        _questionType == 'multiple_choice' ||
        _questionType == 'ordering';
  }

  bool get _isEssay {
    return _questionType == 'essay';
  }

  String _questionTypeLabel(String type) {
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
        return type;
    }
  }

  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_questionType == 'single_choice' &&
        _correctOption == null) {
      _showMessage(
        'يرجى تحديد الإجابة الصحيحة',
      );
      return;
    }

    if (_questionType == 'multiple_choice' &&
        _correctOptions.isEmpty) {
      _showMessage(
        'يرجى تحديد إجابة صحيحة واحدة على الأقل',
      );
      return;
    }

    if (_questionType == 'ordering') {
      if (_optionControllers.any(
        (controller) => controller.text.trim().isEmpty,
      )) {
        _showMessage(
          'يرجى إدخال جميع عناصر الترتيب',
        );
        return;
      }
    }

    if (_questionType == 'essay' &&
        _modelAnswerController.text.trim().isEmpty) {
      _showMessage(
        'يرجى إدخال نموذج الإجابة',
      );
      return;
    }

    final score =
        double.tryParse(_scoreController.text.trim());

    if (score == null || score <= 0) {
      _showMessage(
        'درجة السؤال يجب أن تكون رقمًا أكبر من صفر',
      );
      return;
    }

    int? timeLimitSeconds;

    if (_timeLimitController.text.trim().isNotEmpty) {
      timeLimitSeconds = int.tryParse(
        _timeLimitController.text.trim(),
      );

      if (timeLimitSeconds == null ||
          timeLimitSeconds <= 0) {
        _showMessage(
          'الوقت المحدد يجب أن يكون عددًا صحيحًا أكبر من صفر',
        );
        return;
      }
    }

    if (_maxCharacters != null &&
        _maxCharacters! <= 0) {
      _showMessage(
        'الحد الأقصى لعدد الأحرف يجب أن يكون أكبر من صفر',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      final teacherId =
          widget.sessionManager.currentSession!.uid;

      /*
       * نتأكد مرة أخرى أن المعلم مكلف بهذه المادة.
       */
      final teacherSubjectSnapshot = await firestore
          .collection('teacherSubjects')
          .where(
            'teacherId',
            isEqualTo: teacherId,
          )
          .where(
            'subjectId',
            isEqualTo: widget.subjectId,
          )
          .limit(1)
          .get();

      if (teacherSubjectSnapshot.docs.isEmpty) {
        throw Exception(
          'أنت غير مكلف بهذه المادة.',
        );
      }

      final questionRef =
          firestore.collection('questions').doc();

      final questionData = <String, dynamic>{
        'teacherId': teacherId,
        'subjectId': widget.subjectId,
        'type': _questionType,
        'text': _questionController.text.trim(),
        'score': score,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_needsOptions) {
        questionData['options'] = _optionControllers
            .map(
              (controller) => controller.text.trim(),
            )
            .toList();
      } else if (_questionType == 'true_false') {
        questionData['options'] = [
          'صح',
          'خطأ',
        ];
      }

      if (timeLimitSeconds != null) {
        questionData['timeLimitSeconds'] =
            timeLimitSeconds;
      }

      if (_maxCharacters != null) {
        questionData['maxCharacters'] =
            _maxCharacters;
      }

      final keyData = <String, dynamic>{
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      switch (_questionType) {
        case 'single_choice':
          keyData['correctOption'] = _correctOption;
          break;

        case 'multiple_choice':
          keyData['correctOptions'] =
              List<int>.from(_correctOptions);
          break;

        case 'true_false':
          keyData['correctOption'] = _correctOption;
          break;

        case 'essay':
          keyData['modelAnswer'] =
              _modelAnswerController.text.trim();
          break;

        case 'ordering':
          keyData['correctOrder'] =
              List<int>.from(_correctOrder);
          break;
      }

      final batch = firestore.batch();

      batch.set(
        questionRef,
        questionData,
      );

      batch.set(
        firestore
            .collection('questionKeys')
            .doc(questionRef.id),
        keyData,
      );

      await batch.commit();
/*
try {
  await firestore
      .collection('questions')
      .doc(questionRef.id)
      .set(questionData);

  await firestore
      .collection('questionKeys')
      .doc(questionRef.id)
      .set(keyData);
} catch (error) {
  if (!mounted) {
    return;
  }

  _showMessage(
    'خطأ أثناء حفظ السؤال:\n$error',
  );

  return;
}*/

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إنشاء السؤال بنجاح',
          ),
        ),
      );

      Navigator.of(context).pop(
        questionRef.id,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.toString().replaceFirst(
          'Exception: ',
          '',
        ),
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

  void _changeQuestionType(String? value) {
    if (value == null || _saving) {
      return;
    }

    setState(() {
      _questionType = value;

      _correctOption = null;
      _correctOptions.clear();

      if (value == 'true_false') {
        _correctOption = 0;
      }
    });
  }

  Widget _buildQuestionTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _questionType,
      decoration: const InputDecoration(
        labelText: 'نوع السؤال',
        prefixIcon: Icon(
          Icons.category_outlined,
        ),
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(
          value: 'single_choice',
          child: Text('اختيار من متعدد'),
        ),
        DropdownMenuItem(
          value: 'multiple_choice',
          child: Text('اختيار متعدد'),
        ),
        DropdownMenuItem(
          value: 'true_false',
          child: Text('صح / خطأ'),
        ),
        DropdownMenuItem(
          value: 'essay',
          child: Text('مقالي'),
        ),
        DropdownMenuItem(
          value: 'ordering',
          child: Text('ترتيب'),
        ),
      ],
      onChanged: _changeQuestionType,
    );
  }

  Widget _buildQuestionText() {
    return TextFormField(
      controller: _questionController,
      maxLines: 4,
      textInputAction: TextInputAction.newline,
      decoration: const InputDecoration(
        labelText: 'نص السؤال',
        hintText: 'اكتب السؤال هنا',
        prefixIcon: Icon(
          Icons.help_outline,
        ),
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      validator: (value) {
        if (value == null ||
            value.trim().isEmpty) {
          return 'يرجى إدخال نص السؤال';
        }

        return null;
      },
    );
  }

  Widget _buildSingleChoice() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
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
            const SizedBox(height: 8),
            const Text(
              'حدد اختيارًا واحدًا كإجابة صحيحة.',
            ),
            const SizedBox(height: 12),
            ...List.generate(
              4,
              (index) {
                return Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 10,
                  ),
                  child: Row(
                    children: [
                      Radio<int>(
                        value: index,
                        groupValue:
                            _correctOption,
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() {
                                  _correctOption =
                                      value;
                                });
                              },
                      ),
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
                                value
                                    .trim()
                                    .isEmpty) {
                              return 'أدخل الاختيار';
                            }

                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultipleChoice() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
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
            const SizedBox(height: 8),
            const Text(
              'حدد كل الاختيارات الصحيحة.',
            ),
            const SizedBox(height: 12),
            ...List.generate(
              4,
              (index) {
                return Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 10,
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value:
                            _correctOptions
                                .contains(index),
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() {
                                  if (value ==
                                      true) {
                                    _correctOptions
                                        .add(index);
                                  } else {
                                    _correctOptions
                                        .remove(
                                      index,
                                    );
                                  }
                                });
                              },
                      ),
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
                                value
                                    .trim()
                                    .isEmpty) {
                              return 'أدخل الاختيار';
                            }

                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrueFalse() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الإجابة الصحيحة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            RadioListTile<int>(
              value: 0,
              groupValue: _correctOption,
              title: const Text('صح'),
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        _correctOption = value;
                      });
                    },
            ),
            RadioListTile<int>(
              value: 1,
              groupValue: _correctOption,
              title: const Text('خطأ'),
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        _correctOption = value;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEssay() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'نموذج الإجابة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'يستخدم هذا النموذج كمرجع للتصحيح اليدوي.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _modelAnswerController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'نموذج الإجابة',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (_questionType != 'essay') {
                  return null;
                }

                if (value == null ||
                    value.trim().isEmpty) {
                  return 'يرجى إدخال نموذج الإجابة';
                }

                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdering() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'عناصر الترتيب',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'أدخل العناصر بالترتيب الصحيح من الأول إلى الأخير.',
            ),
            const SizedBox(height: 12),
            ...List.generate(
              4,
              (index) {
                return Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 10,
                  ),
                  child: TextFormField(
                    controller:
                        _optionControllers[index],
                    decoration: InputDecoration(
                      labelText:
                          'العنصر ${index + 1}',
                      prefixIcon: CircleAvatar(
                        radius: 12,
                        child: Text(
                          '${index + 1}',
                        ),
                      ),
                      border:
                          const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'أدخل العنصر';
                      }

                      return null;
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreAndTime() {
    return Row(
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
              prefixIcon: Icon(
                Icons.star_outline,
              ),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null ||
                  value.trim().isEmpty) {
                return 'أدخل الدرجة';
              }

              final score =
                  double.tryParse(value.trim());

              if (score == null ||
                  score <= 0) {
                return 'درجة غير صحيحة';
              }

              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _timeLimitController,
            keyboardType:
                TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'الوقت بالثواني',
              hintText: 'اختياري',
              prefixIcon: Icon(
                Icons.timer_outlined,
              ),
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEssayCharacterLimit() {
    if (!_isEssay) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DropdownButtonFormField<int?>(
        value: _maxCharacters,
        decoration: const InputDecoration(
          labelText: 'الحد الأقصى للإجابة',
          prefixIcon: Icon(
            Icons.text_fields_outlined,
          ),
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem<int?>(
            value: null,
            child: Text('بدون حد'),
          ),
          DropdownMenuItem<int?>(
            value: 100,
            child: Text('100 حرف'),
          ),
          DropdownMenuItem<int?>(
            value: 250,
            child: Text('250 حرف'),
          ),
          DropdownMenuItem<int?>(
            value: 500,
            child: Text('500 حرف'),
          ),
          DropdownMenuItem<int?>(
            value: 1000,
            child: Text('1000 حرف'),
          ),
          DropdownMenuItem<int?>(
            value: 2000,
            child: Text('2000 حرف'),
          ),
        ],
        onChanged: _saving
            ? null
            : (value) {
                setState(() {
                  _maxCharacters = value;
                });
              },
      ),
    );
  }

  Widget _buildQuestionContent() {
    switch (_questionType) {
      case 'single_choice':
        return _buildSingleChoice();

      case 'multiple_choice':
        return _buildMultipleChoice();

      case 'true_false':
        return _buildTrueFalse();

      case 'essay':
        return _buildEssay();

      case 'ordering':
        return _buildOrdering();

      default:
        return const SizedBox.shrink();
    }
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
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .stretch,
                        children: [
                          const Text(
                            'بنك أسئلة المعلم',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'نوع السؤال: ${_questionTypeLabel(_questionType)}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              )
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'بيانات السؤال',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildQuestionTypeDropdown(),
                  const SizedBox(height: 16),
                  _buildQuestionText(),
                  const SizedBox(height: 20),
                  _buildQuestionContent(),
                  _buildEssayCharacterLimit(),
                  const SizedBox(height: 16),
                  _buildScoreAndTime(),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed:
                          _saving ? null : _saveQuestion,
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
                              Icons.save_outlined,
                            ),
                      label: Text(
                        _saving
                            ? 'جاري الحفظ...'
                            : 'حفظ السؤال',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
