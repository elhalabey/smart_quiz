import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'result_print_service.dart';

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _formatNumber(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

String _typeLabel(String type) {
  switch (type) {
    case 'single_choice': return 'اختيار من متعدد';
    case 'multiple_choice': return 'اختيارات متعددة';
    case 'true_false': return 'صح / خطأ';
    case 'essay': return 'سؤال مقالي';
    case 'ordering': return 'ترتيب';
    default: return 'سؤال';
  }
}

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
  final percentage = maxScore > 0 ? totalScore / maxScore * 100 : 0;
  final buffer = StringBuffer();

  buffer.write('''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<title>نتيجة ${_escapeHtml(studentName)} - ${_escapeHtml(quizTitle)}</title>
<style>
@page { size: A4; margin: 15mm; }
* { box-sizing: border-box; }
body { margin:0; color:#111; background:#fff; font-family:Tahoma,Arial,sans-serif; direction:rtl; line-height:1.7; font-size:14px; }
.header { text-align:center; border-bottom:2px solid #222; padding-bottom:14px; margin-bottom:18px; }
.title { font-size:25px; font-weight:bold; }
.subtitle { margin-top:5px; font-size:18px; }
.student { font-size:17px; margin-top:5px; }
.summary { display:grid; grid-template-columns:repeat(4,1fr); gap:8px; margin-bottom:24px; }
.summary-box { border:1px solid #777; border-radius:6px; padding:9px; text-align:center; }
.summary-label { font-size:12px; color:#555; }
.summary-value { font-size:17px; font-weight:bold; margin-top:3px; }
.question { border:1px solid #bbb; border-radius:7px; padding:13px; margin-bottom:14px; page-break-inside:avoid; }
.question-header { display:flex; justify-content:space-between; gap:12px; font-weight:bold; margin-bottom:7px; }
.question-number { font-size:16px; }
.question-type { color:#666; font-size:12px; font-weight:normal; }
.question-text { font-size:15px; font-weight:600; margin-bottom:10px; }
.answer-box { margin-top:7px; padding:9px 11px; border-right:4px solid #555; background:#f5f5f5; }
.label { font-weight:bold; }
.score { margin-top:9px; font-weight:bold; }
.footer { border-top:1px solid #777; margin-top:24px; padding-top:10px; text-align:center; font-size:11px; color:#555; }
@media print { body { -webkit-print-color-adjust:exact; print-color-adjust:exact; } }
</style>
</head>
<body>
<div class="header">
<div class="title">تقرير نتيجة الطالب</div>
<div class="subtitle">${_escapeHtml(quizTitle)}</div>
<div class="student">الطالب: ${_escapeHtml(studentName)}</div>
</div>
<div class="summary">
<div class="summary-box"><div class="summary-label">الدرجة</div><div class="summary-value">${_formatNumber(totalScore)} / ${_formatNumber(maxScore)}</div></div>
<div class="summary-box"><div class="summary-label">النسبة</div><div class="summary-value">${percentage.toStringAsFixed(1)}%</div></div>
<div class="summary-box"><div class="summary-label">التصحيح التلقائي</div><div class="summary-value">${_formatNumber(autoScore)}</div></div>
<div class="summary-box"><div class="summary-label">التصحيح اليدوي</div><div class="summary-value">${_formatNumber(manualScore)}</div></div>
</div>
''');

  for (final q in questions) {
    buffer.write('''
<div class="question">
<div class="question-header"><div class="question-number">السؤال ${q.number}</div><div class="question-type">${_typeLabel(q.type)}</div></div>
<div class="question-text">${_escapeHtml(q.text)}</div>
<div class="answer-box"><span class="label">إجابة الطالب:</span> ${_escapeHtml(q.studentAnswer)}</div>
<div class="answer-box"><span class="label">الإجابة الصحيحة:</span> ${_escapeHtml(q.correctAnswer)}</div>
<div class="score">الدرجة: ${_formatNumber(q.earnedScore)} / ${_formatNumber(q.score)}</div>
</div>
''');
  }

  buffer.write('''
<div class="footer">${status == 'published' ? 'النتيجة منشورة' : 'النتيجة قيد المراجعة'}</div>
</body>
</html>
''');

  final printWindow = web.window.open('', '_blank');
  if (printWindow == null) throw Exception('تعذر فتح نافذة الطباعة.');

  printWindow.document.open();
  printWindow.document.write(buffer.toString().toJS);
  printWindow.document.close();
  await Future<void>.delayed(const Duration(milliseconds:500));
  printWindow.focus();
  printWindow.print();
}
