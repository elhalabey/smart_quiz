import 'result_print_service.dart';

Future<void> printStudentResultImpl({
  required String quizTitle,
  required String studentName,
  required double totalScore,
  required double maxScore,
  required double autoScore,
  required double manualScore,
  required String status,
  required List<ResultPrintQuestion> questions,
}) async {
  throw UnsupportedError('طباعة نتيجة الطالب متاحة على الويب فقط.');
}
