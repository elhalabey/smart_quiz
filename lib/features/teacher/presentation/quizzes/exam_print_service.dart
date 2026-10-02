import 'exam_print_service_stub.dart'
    if (dart.library.html) 'exam_print_service_web.dart';

class PrintQuestion {
  final int number;
  final String text;
  final String type;
  final List<String> options;
  final double score;

  const PrintQuestion({
    required this.number,
    required this.text,
    required this.type,
    required this.options,
    required this.score,
  });
}

Future<void> printExam({
  required String title,
  required String subject,
  required List<PrintQuestion> questions,
}) {
  return printExamImpl(
    title: title,
    subject: subject,
    questions: questions,
  );
}
