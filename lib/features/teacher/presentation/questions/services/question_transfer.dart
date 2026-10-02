import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuestionImportResult {
  final int created;
  final int updated;
  final List<String> errors;

  const QuestionImportResult({
    required this.created,
    required this.updated,
    required this.errors,
  });
}

class QuestionTransfer {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static const headers = [
    'questionId',
    'subjectId',
    'unitName',
    'type',
    'questionText',
    'option1',
    'option2',
    'option3',
    'option4',
    'correctOption',
    'correctOptions',
    'correctOrder',
    'modelAnswer',
    'score',
    'timeLimitSeconds',
    'maxCharacters',
  ];

  static Future<String> exportCsv() async {
    final teacherId = _auth.currentUser?.uid;
    if (teacherId == null || teacherId.isEmpty) {
      throw StateError('لم يتم العثور على جلسة المعلم.');
    }

    final questions = await _firestore
        .collection('questions')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    // questionKeys لا تحتوي teacherId في البيانات القديمة، لذلك لا نستخدم
    // collection().get() هنا؛ قواعد Firestore تسمح للمعلم بقراءة المفتاح
    // فقط إذا كان السؤال المقابل يخصه.
    final keyById = <String, Map<String, dynamic>>{};
    for (final question in questions.docs) {
      try {
        final keySnapshot = await _firestore
            .collection('questionKeys')
            .doc(question.id)
            .get();
        if (keySnapshot.exists) {
          keyById[question.id] = keySnapshot.data() ?? <String, dynamic>{};
        }
      } on FirebaseException {
        // سؤال قديم بلا questionKeys أو غير قابل للقراءة لا يمنع تصدير باقي البنك.
      }
    }

    final units = await _firestore
        .collection('questionUnit')
        .where('teacherId', isEqualTo: teacherId)
        .get();
    final unitById = <String, String>{
      for (final doc in units.docs)
        doc.id: doc.data()['unitName']?.toString() ?? '',
    };

    final rows = <List<String>>[headers];
    for (final doc in questions.docs) {
      final data = doc.data();
      final key = keyById[doc.id] ?? <String, dynamic>{};
      final options = (data['options'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];

      rows.add([
        doc.id,
        data['subjectId']?.toString() ?? '',
        unitById[doc.id] ?? '',
        data['type']?.toString() ?? '',
        data['text']?.toString() ?? '',
        _option(options, 0),
        _option(options, 1),
        _option(options, 2),
        _option(options, 3),
        _stringValue(key['correctOption']),
        _joinInts(key['correctOptions']),
        _joinInts(key['correctOrder']),
        key['modelAnswer']?.toString() ?? '',
        _stringValue(data['score']),
        _stringValue(data['timeLimitSeconds']),
        _stringValue(data['maxCharacters']),
      ]);
    }

    return rows.map((row) => row.map(_escapeCsv).join(',')).join('\r\n');
  }

  static String _option(List<String> options, int index) =>
      index < options.length ? options[index] : '';

  static String _stringValue(dynamic value) => value == null ? '' : value.toString();

  static String _joinInts(dynamic value) {
    if (value is! List) return '';
    return value.map((e) => e.toString()).join('|');
  }

  static String _escapeCsv(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.contains(',') || normalized.contains('"') || normalized.contains('\n')) {
      return '"${normalized.replaceAll('"', '""')}"';
    }
    return normalized;
  }

  static List<List<String>> parseCsv(String csv) {
    final text = csv.replaceFirst('\uFEFF', '');
    final rows = <List<String>>[];
    final row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
      } else if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        row.add(field.toString());
        field.clear();
      } else if (char == '\n') {
        row.add(field.toString());
        field.clear();
        if (row.any((cell) => cell.trim().isNotEmpty)) {
          rows.add(List<String>.from(row));
        }
        row.clear();
      } else if (char != '\r') {
        field.write(char);
      }
    }
    row.add(field.toString());
    if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(List<String>.from(row));
    return rows;
  }

  static Future<QuestionImportResult> importCsv(String csv) async {
    final teacherId = _auth.currentUser?.uid;
    if (teacherId == null || teacherId.isEmpty) {
      throw StateError('لم يتم العثور على جلسة المعلم.');
    }

    final rows = parseCsv(csv);
    if (rows.isEmpty) throw const FormatException('الملف فارغ.');

    final header = rows.first.map((e) => e.trim()).toList();
    int idx(String name) => header.indexOf(name);
    final typeIndex = idx('type');
    final textIndex = idx('questionText');
    final subjectIndex = idx('subjectId');
    final idIndex = idx('questionId');
    if (typeIndex < 0 || textIndex < 0 || subjectIndex < 0 || idIndex < 0) {
      throw const FormatException(
        'صيغة الملف غير صحيحة. يجب أن يحتوي على questionId و subjectId و type و questionText.',
      );
    }

    final teacherSubjects = await _firestore
        .collection('teacherSubjects')
        .where('teacherId', isEqualTo: teacherId)
        .get();
    final allowedSubjects = teacherSubjects.docs
        .map((d) => d.data()['subjectId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    var created = 0;
    var updated = 0;
    final errors = <String>[];

    for (var i = 1; i < rows.length; i++) {
      final rowNumber = i + 1;
      final row = rows[i];
      String cell(String name) {
        final index = idx(name);
        return index >= 0 && index < row.length ? row[index].trim() : '';
      }

      final questionId = cell('questionId');
      final subjectId = cell('subjectId');
      final type = cell('type');
      final questionText = cell('questionText');
      final unitName = cell('unitName');

      try {
        if (subjectId.isEmpty || !allowedSubjects.contains(subjectId)) {
          throw FormatException('المعلم غير مكلف بالمادة $subjectId.');
        }
        if (!{'single_choice', 'multiple_choice', 'true_false', 'essay', 'ordering'}
            .contains(type)) {
          throw FormatException('نوع السؤال غير مدعوم: $type');
        }
        if (questionText.isEmpty) throw const FormatException('نص السؤال فارغ.');

        final score = double.tryParse(cell('score')) ?? 1;
        if (score <= 0) throw const FormatException('الدرجة يجب أن تكون أكبر من صفر.');

        final options = [cell('option1'), cell('option2'), cell('option3'), cell('option4')]
            .where((e) => e.isNotEmpty)
            .toList();
        if (type == 'true_false') {
          options
            ..clear()
            ..addAll(['صح', 'خطأ']);
        }
        if ((type == 'single_choice' || type == 'multiple_choice' || type == 'ordering') &&
            options.length < 2) {
          throw const FormatException('يجب إدخال خيارين على الأقل.');
        }

        final keyData = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final correctOption = int.tryParse(cell('correctOption'));
        if (type == 'single_choice' || type == 'true_false') {
          if (correctOption == null || correctOption < 0 || correctOption >= options.length) {
            throw const FormatException('correctOption غير صحيح.');
          }
          keyData['correctOption'] = correctOption;
        } else if (type == 'multiple_choice') {
          final values = _parseInts(cell('correctOptions'));
          if (values.isEmpty || values.any((v) => v < 0 || v >= options.length)) {
            throw const FormatException('correctOptions غير صحيحة.');
          }
          keyData['correctOptions'] = values;
        } else if (type == 'ordering') {
          final values = _parseInts(cell('correctOrder'));
          if (values.length != options.length || values.any((v) => v < 0 || v >= options.length)) {
            throw const FormatException('correctOrder غير صحيح.');
          }
          keyData['correctOrder'] = values;
        } else if (type == 'essay') {
          keyData['modelAnswer'] = cell('modelAnswer');
        }

        final questionRef = questionId.isEmpty
            ? _firestore.collection('questions').doc()
            : _firestore.collection('questions').doc(questionId);

        if (questionId.isNotEmpty) {
          final existing = await questionRef.get();
          if (!existing.exists) {
            throw FormatException('السؤال $questionId غير موجود. اترك ID فارغًا لإنشاء سؤال جديد.');
          }
          final existingData = existing.data() ?? <String, dynamic>{};
          if (existingData['teacherId']?.toString() != teacherId) {
            throw const FormatException('السؤال لا يخص هذا المعلم.');
          }
        }

        final questionData = <String, dynamic>{
          'teacherId': teacherId,
          'subjectId': subjectId,
          'type': type,
          'text': questionText,
          'options': options,
          'score': score,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        final timeLimit = int.tryParse(cell('timeLimitSeconds'));
        if (timeLimit != null && timeLimit > 0) questionData['timeLimitSeconds'] = timeLimit;
        final maxCharacters = int.tryParse(cell('maxCharacters'));
        if (maxCharacters != null && maxCharacters > 0) questionData['maxCharacters'] = maxCharacters;
        if (questionId.isEmpty) questionData['createdAt'] = FieldValue.serverTimestamp();

        final batch = _firestore.batch();
        batch.set(questionRef, questionData, SetOptions(merge: true));
        batch.set(
          _firestore.collection('questionKeys').doc(questionRef.id),
          keyData,
          SetOptions(merge: true),
        );
        final unitRef = _firestore.collection('questionUnit').doc(questionRef.id);
        if (unitName.isEmpty) {
          batch.delete(unitRef);
        } else {
          batch.set(unitRef, {
            'questionId': questionRef.id,
            'teacherId': teacherId,
            'subjectId': subjectId,
            'unitName': unitName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
        if (questionId.isEmpty) {
          created++;
        } else {
          updated++;
        }
      } catch (e) {
        errors.add('الصف $rowNumber${questionId.isEmpty ? '' : ' ($questionId)'}: $e');
      }
    }

    return QuestionImportResult(created: created, updated: updated, errors: errors);
  }

  static List<int> _parseInts(String value) {
    if (value.trim().isEmpty) return [];
    return value
        .split('|')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
  }
}
