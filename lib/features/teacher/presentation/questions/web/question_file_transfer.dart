import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadQuestionsCsv(String csv) async {
  final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', 'questions.csv')
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<String?> pickQuestionsCsv() async {
  final input = html.FileUploadInputElement()..accept = '.csv,text/csv';
  input.click();
  await input.onChange.first;
  final file = input.files?.first;
  if (file == null) return null;
  final reader = html.FileReader();
  reader.readAsText(file, 'utf-8');
  await reader.onLoad.first;
  return reader.result as String?;
}
