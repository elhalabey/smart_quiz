import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'exam_print_service.dart';

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _typeLabel(String type) {
  switch (type) {
    case 'single_choice':
      return 'اختيار واحد';
    case 'multiple_choice':
      return 'اختيارات متعددة';
    case 'true_false':
      return 'صح / خطأ';
    case 'essay':
      return 'سؤال مقالي';
    case 'ordering':
      return 'ترتيب';
    default:
      return type;
  }
}

Future<void> printExamImpl({
  required String title,
  required String subject,
  required List<PrintQuestion> questions,
}) async {
  final buffer = StringBuffer();

  buffer.write('''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">

<title>${_escapeHtml(title)}</title>

<style>
  @page {
    size: A4;
    margin: 18mm;
  }

  * {
    box-sizing: border-box;
  }

  body {
    font-family: Tahoma, Arial, sans-serif;
    direction: rtl;
    color: #111;
    background: white;
    margin: 0;
    line-height: 1.7;
    font-size: 15px;
  }

  .header {
    text-align: center;
    border-bottom: 2px solid #222;
    padding-bottom: 14px;
    margin-bottom: 18px;
  }

  .title {
    font-size: 24px;
    font-weight: bold;
    margin-bottom: 4px;
  }

  .subject {
    font-size: 17px;
  }

  .info {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px 30px;
    margin: 18px 0 25px;
  }

  .field {
    border-bottom: 1px solid #555;
    padding: 5px;
    min-height: 32px;
  }

  .question {
    margin-bottom: 22px;
    page-break-inside: avoid;
  }

  .question-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 15px;
    font-weight: bold;
    margin-bottom: 8px;
  }

  .question-number {
    font-size: 17px;
  }

  .score {
    white-space: nowrap;
    font-size: 13px;
  }

  .question-text {
    font-size: 16px;
    margin-bottom: 8px;
  }

  .type {
    color: #555;
    font-size: 12px;
    margin-bottom: 8px;
  }

  .options {
    margin-right: 20px;
  }

  .option {
    margin: 5px 0;
  }

  .essay-lines {
    margin-top: 10px;
  }

  .line {
    border-bottom: 1px solid #aaa;
    height: 30px;
  }

  .footer {
    margin-top: 35px;
    padding-top: 10px;
    border-top: 1px solid #777;
    text-align: center;
    font-size: 12px;
  }

  @media print {
    body {
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
  }
</style>
</head>

<body>

<div class="header">
  <div class="title">${_escapeHtml(title)}</div>
  <div class="subject">المادة: ${_escapeHtml(subject)}</div>
</div>

<div class="info">
  <div class="field">اسم الطالب: ______________________________</div>
  <div class="field">التاريخ: __________________</div>
  <div class="field">الصف: _____________________</div>
  <div class="field">الدرجة: __________ / __________</div>
</div>
''');

  for (final question in questions) {
    buffer.write('''
<div class="question">

  <div class="question-header">
    <div class="question-number">
      السؤال ${question.number}
    </div>

    <div class="score">
      الدرجة: ${question.score}
    </div>
  </div>

  <div class="question-text">
    ${_escapeHtml(question.text)}
  </div>

  <div class="type">
    ${_typeLabel(question.type)}
  </div>
''');

    if (question.type == 'essay') {
      buffer.write('''
  <div class="essay-lines">
    <div class="line"></div>
    <div class="line"></div>
    <div class="line"></div>
    <div class="line"></div>
    <div class="line"></div>
  </div>
''');
    } else if (question.type == 'true_false') {
      buffer.write('''
  <div class="options">
    <div class="option">☐ صح</div>
    <div class="option">☐ خطأ</div>
  </div>
''');
    } else if (question.type == 'ordering') {
  buffer.write('''
  <div class="options">
    ${question.options.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final option = _escapeHtml(entry.value);
      return '''
      <div class="option">
        $index) $option
      </div>
      ''';
    }).join()}
  </div>
''');
    } else {
      buffer.write('<div class="options">');

      for (var i = 0; i < question.options.length; i++) {
        final letters = ['أ', 'ب', 'ج', 'د', 'هـ', 'و'];
        final letter = i < letters.length ? letters[i] : '${i + 1}';

        buffer.write('''
        <div class="option">
          ☐ $letter) ${_escapeHtml(question.options[i])}
        </div>
''');
      }

      buffer.write('</div>');
    }

    buffer.write('</div>');
  }

  buffer.write('''
<div class="footer">
  اختبار الطالب الذكي
</div>

</body>
</html>
''');

  final printWindow = web.window.open('', '_blank');

  if (printWindow == null) {
    throw Exception('تعذر فتح نافذة الطباعة.');
  }

  printWindow.document.open();
printWindow.document.write(
  buffer.toString().toJS,
);
  printWindow.document.close();

  await Future<void>.delayed(
    const Duration(milliseconds: 500),
  );

  printWindow.focus();
  printWindow.print();
}
