import 'result_print_service_stub.dart'
    if (dart.library.html) 'result_print_service_web.dart';

class ResultPrintQuestion {
  final int number;
  final String text;
  final String type;
  final String studentAnswer;
  final String correctAnswer;
  final double score;
  final double earnedScore;

  const ResultPrintQuestion({
    required this.number,
    required this.text,
    required this.type,
    required this.studentAnswer,
    required this.correctAnswer,
    required this.score,
    required this.earnedScore,
  });
}

Future<void> printStudentResult({
  required String quizTitle,
  required String studentName,
  required double totalScore,
  required double maxScore,
  required double autoScore,
  required double manualScore,
  required String status,
  required List<ResultPrintQuestion> questions,
}) {
  return printStudentResultImpl(
    quizTitle: quizTitle,
    studentName: studentName,
    totalScore: totalScore,
    maxScore: maxScore,
    autoScore: autoScore,
    manualScore: manualScore,
    status: status,
    questions: questions,
  );
}
