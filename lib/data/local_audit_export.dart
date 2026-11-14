import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../application/local_audit_service.dart';
import '../domain/audit_engine.dart';
import '../domain/local_audit_result.dart';
import 'local_audit_database.dart';

class LocalAuditExport {
  static Uint8List encode(CycleRecord cycle, List<LocalAuditResult> history) {
    final workbook = Excel.createExcel();
    final initial = workbook.getDefaultSheet()!;
    final summary = workbook['حالات التدقيق'];
    final management = workbook['الإدارة'];
    final agent = workbook['الوكيل'];
    final log = workbook['سجل التدقيق'];
    workbook.setDefaultSheet(summary.sheetName);
    workbook.delete(initial);

    _append(summary, [
      'رقم المستخدم',
      'الحالة',
      'نتيجة المطابقة',
      'الوجهة',
      'التاريخ',
    ]);
    _append(log, [
      'رقم المستخدم',
      'الحالة',
      'نتيجة المطابقة',
      'الوجهة',
      'التاريخ',
      'طريقة التدقيق',
    ]);
    final current = <String, LocalAuditResult>{};
    for (final result in history) {
      current.putIfAbsent(result.memberId, () => result);
      _append(log, [..._status(result), result.individual ? 'فردي' : 'جماعي']);
    }

    final managementMarks = <int, LocalAuditResult>{};
    final agentMarks = <int, (SourceRow, String)>{};
    final targets = <String, Sheet>{};
    final usedNames =
        workbook.tables.keys.map((name) => name.toLowerCase()).toSet();
    for (final result in current.values) {
      _append(summary, _status(result));
      final source = result.managementRow;
      final color = result.color;
      final target = result.target;
      if (source == null || color == null || target == null) continue;
      managementMarks.putIfAbsent(source.rowNumber, () => result);
      for (final row in result.agentRows) {
        agentMarks.putIfAbsent(row.rowNumber, () => (row, color));
      }
      final sheet = targets.putIfAbsent(
        target,
        () => workbook[_sheetName(target, usedNames)],
      );
      _append(sheet, source.values);
    }

    final managementRows = cycleRows(cycle.snapshots['management']);
    for (var i = 0; i < managementRows.length; i++) {
      final row = managementRows[i];
      final mark = managementMarks[i + 1];
      _append(
        management,
        row,
        _equal(row, mark?.managementRow?.values) ? mark?.color : null,
      );
    }
    final agentRows = cycleRows(cycle.snapshots['agent']);
    for (var i = 0; i < agentRows.length; i++) {
      final row = agentRows[i];
      final mark = agentMarks[i + 1];
      _append(agent, row, _equal(row, mark?.$1.values) ? mark?.$2 : null);
    }
    final bytes = workbook.encode();
    if (bytes == null) throw StateError('تعذر إنشاء ملف Excel.');
    return Uint8List.fromList(bytes);
  }

  static List<String> _status(LocalAuditResult result) => [
    result.memberId,
    result.audited ? 'مدقق' : 'غير مدقق',
    result.classification.label,
    result.target ?? '',
    result.auditedAt.toLocal().toIso8601String(),
  ];

  static bool _equal(List<String> row, List<String>? saved) {
    if (saved == null || row.length != saved.length) return false;
    for (var i = 0; i < row.length; i++) {
      if (row[i] != saved[i]) return false;
    }
    return true;
  }

  static void _append(Sheet sheet, List<String> row, [String? color]) {
    final index = sheet.maxRows;
    sheet.appendRow(
      row.isEmpty ? [TextCellValue('')] : row.map(TextCellValue.new).toList(),
    );
    if (color == null) return;
    final style = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('FF${color.substring(1)}'),
    );
    for (var i = 0; i < row.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: index))
          .cellStyle = style;
    }
  }

  static String _sheetName(String target, Set<String> used) {
    final base =
        target.replaceAll(RegExp(r"[\[\]:*?/\\'\x00-\x1f]"), '_').trim();
    final stem = base.isEmpty ? 'الوجهة' : base;
    var sequence = 1;
    while (true) {
      final suffix = sequence == 1 ? '' : ' ($sequence)';
      final prefix = String.fromCharCodes(stem.runes.take(31 - suffix.length));
      final name = '$prefix$suffix';
      if (used.add(name.toLowerCase())) return name;
      sequence++;
    }
  }
}
