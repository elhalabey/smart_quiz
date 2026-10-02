import 'exam_print_service.dart';

Future<void> printExamImpl({
  required String title,
  required String subject,
  required List<PrintQuestion> questions,
}) async {
  throw UnsupportedError('طباعة الامتحان متاحة على الويب فقط.');
}
