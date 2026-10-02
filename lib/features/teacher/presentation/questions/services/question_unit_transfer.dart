import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QuestionUnitImportResult {
  final int updated;
  final int removed;
  final List<String> errors;

  const QuestionUnitImportResult({
    required this.updated,
    required this.removed,
    required this.errors,
  });
}

class QuestionUnitTransfer {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<String> exportCsv() async {
    final teacherId = _auth.currentUser?.uid;
    if (teacherId == null || teacherId.isEmpty) {
      throw StateError('لم يتم العثور على جلسة المعلم.');
    }

    final questions = await _firestore
        .collection('questions')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    final units = await _firestore
        .collection('questionUnit')
        .where('teacherId', isEqualTo: teacherId)
        .get();

    final unitByQuestionId = <String, String>{};
    for (final doc in units.docs) {
      unitByQuestionId[doc.id] = doc.data()['unitName']?.toString() ?? '';
    }

    final rows = <List<String>>[
      ['questionId', 'subjectId', 'unitName'],
    ];

    for (final doc in questions.docs) {
      final data = doc.data();
      rows.add([
        doc.id,
        data['subjectId']?.toString() ?? '',
        unitByQuestionId[doc.id] ?? '',
      ]);
    }

    return rows.map((row) => row.map(_escapeCsv).join(',')).join('\r\n');
  }

  static String _escapeCsv(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.contains(',') ||
        normalized.contains('"') ||
        normalized.contains('\n')) {
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
    if (row.any((cell) => cell.trim().isNotEmpty)) {
      rows.add(List<String>.from(row));
    }
    return rows;
  }

  static Future<QuestionUnitImportResult> importCsv(String csv) async {
    final teacherId = _auth.currentUser?.uid;
    if (teacherId == null || teacherId.isEmpty) {
      throw StateError('لم يتم العثور على جلسة المعلم.');
    }

    final rows = parseCsv(csv);
    if (rows.isEmpty) {
      throw const FormatException('الملف فارغ.');
    }

    final header = rows.first.map((e) => e.trim()).toList();
    final idIndex = header.indexOf('questionId');
    final unitIndex = header.indexOf('unitName');
    if (idIndex < 0 || unitIndex < 0) {
      throw const FormatException(
        'صيغة الملف غير صحيحة. يجب أن يحتوي على questionId و unitName.',
      );
    }

    var updated = 0;
    var removed = 0;
    final errors = <String>[];
    WriteBatch? batch;
    var batchCount = 0;

    Future<void> commitBatch() async {
      if (batchCount == 0 || batch == null) return;
      await batch!.commit();
      batch = null;
      batchCount = 0;
    }

    for (var i = 1; i < rows.length; i++) {
      final rowNumber = i + 1;
      final row = rows[i];
      final questionId = idIndex < row.length ? row[idIndex].trim() : '';
      final unitName = unitIndex < row.length ? row[unitIndex].trim() : '';

      if (questionId.isEmpty) {
        errors.add('الصف $rowNumber: questionId فارغ.');
        continue;
      }

      try {
        final questionRef = _firestore.collection('questions').doc(questionId);
        final questionSnapshot = await questionRef.get();
        if (!questionSnapshot.exists) {
          errors.add('الصف $rowNumber: السؤال $questionId غير موجود.');
          continue;
        }

        final questionData = questionSnapshot.data() ?? <String, dynamic>{};
        if (questionData['teacherId']?.toString() != teacherId) {
          errors.add('الصف $rowNumber: السؤال $questionId لا يخص هذا المعلم.');
          continue;
        }

        batch ??= _firestore.batch();
        final unitRef = _firestore.collection('questionUnit').doc(questionId);

        if (unitName.isEmpty) {
          batch!.delete(unitRef);
          removed++;
        } else {
          batch!.set(
            unitRef,
            {
              'questionId': questionId,
              'teacherId': teacherId,
              'subjectId': questionData['subjectId']?.toString() ?? '',
              'unitName': unitName,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          updated++;
        }

        batchCount++;
        if (batchCount >= 400) {
          await commitBatch();
        }
      } catch (e) {
        errors.add('الصف $rowNumber ($questionId): $e');
      }
    }

    await commitBatch();
    return QuestionUnitImportResult(
      updated: updated,
      removed: removed,
      errors: errors,
    );
  }
}
