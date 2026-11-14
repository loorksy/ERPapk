import 'package:file_picker/file_picker.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../data/import_service.dart';

Future<ImportedSheet?> pickAuditFile(BuildContext context) async {
  final selection = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'csv'],
    withData: true,
  );
  if (selection == null || !context.mounted) return null;
  final file = selection.files.single;
  final bytes = file.bytes;
  if (bytes == null) throw const FormatException('تعذرت قراءة الملف المحدد.');
  final ImportedSheet sheet;
  if (file.extension?.toLowerCase() == 'csv') {
    const encodings = {
      'auto': 'تلقائي (UTF-8 أو علامة UTF-16)',
      'windows-1256': 'Windows-1256 عربي',
      'utf-8': 'UTF-8',
      'utf-16le': 'UTF-16 LE',
      'utf-16be': 'UTF-16 BE',
    };
    final encoding = await _choose(context, 'ترميز CSV', encodings);
    if (encoding == null) return null;
    sheet = ImportService.decodeCsv(
      bytes,
      encoding: encoding == 'auto' ? null : encoding,
    );
  } else {
    final book = ImportService.readXlsx(bytes);
    if (book.sheetNames.isEmpty) {
      throw const FormatException('ملف Excel لا يحتوي أوراق عمل.');
    }
    final title = book.sheetNames.length == 1
        ? book.sheetNames.single
        : await _choose(context, 'اختر ورقة العمل', {
            for (final name in book.sheetNames) name: name,
          });
    if (title == null) return null;
    sheet = book.selectSheet(title);
  }
  return ImportedSheet(
    '${file.name} · ${sheet.name}',
    sheet.rows,
    sheet.nonTextCells,
  );
}

Future<String?> _choose(
  BuildContext context,
  String title,
  Map<String, String> choices,
) => showDialog<String>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(title),
    children: [
      for (final choice in choices.entries)
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, choice.key),
          child: Text(choice.value),
        ),
    ],
  ),
);
