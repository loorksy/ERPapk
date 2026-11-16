// In-memory stand-in for the Google Sheets API used by the audit services.
import 'package:lork_audit_standalone/erp/normalize.dart';
import 'package:lork_audit_standalone/google/sheets_client.dart';

class FakeSheets implements SheetsApi {
  final books = <String, Map<String, List<List<String>>>>{};
  final ids = <String, Map<String, int>>{};
  final colors = <String, Map<int, String>>{}; // "ss|sheetId" -> row -> rgb
  final log = <String>[];
  int _next = 100;

  void add(String ss, String title, List<List<String>> rows) {
    books.putIfAbsent(ss, () => {})[title] = rows.map((r) => [...r]).toList();
    ids.putIfAbsent(ss, () => {})[title] = _next++;
  }

  (String, String, int, int?) _range(String range) {
    final m =
        RegExp(
          r"^'((?:[^']|'')*)'!([A-Z]+)(\d*)(?::([A-Z]+)(\d*))?$",
        ).firstMatch(range)!;
    final title = m.group(1)!.replaceAll("''", "'");
    final col = m.group(2)!;
    final row = m.group(3)!.isEmpty ? 1 : int.parse(m.group(3)!);
    final end =
        m.group(5) == null || m.group(5)!.isEmpty
            ? null
            : int.parse(m.group(5)!);
    return (title, col, row, end);
  }

  @override
  Future<List<SpreadsheetFile>> listSpreadsheets() async => [
    for (final k in books.keys) SpreadsheetFile(k, 'ملف $k'),
  ];

  @override
  Future<SpreadsheetMeta> getSpreadsheet(String id) async {
    log.add('GET meta $id');
    final b = books[id] ?? (throw SheetsApiException('missing', status: 404));
    return SpreadsheetMeta(
      spreadsheetId: id,
      spreadsheetUrl: 'https://x/$id',
      sheets: [for (final t in b.keys) SheetProps(ids[id]![t]!, t)],
    );
  }

  @override
  Future<List<List<String>>> valuesGet(String id, String range) async {
    log.add('GET values $id $range');
    final (title, _, row, end) = _range(range);
    final rows =
        books[id]![title] ??
        (throw SheetsApiException('Unable to parse range', status: 400));
    final from = row - 1;
    final to =
        end == null ? rows.length : (end < rows.length ? end : rows.length);
    if (from >= rows.length) return [];
    final out = rows.sublist(from, to).map((r) => [...r]).toList();
    while (out.isNotEmpty && out.last.every((c) => c.isEmpty)) {
      out.removeLast();
    }
    return out;
  }

  void _write(
    String id,
    String title,
    int col,
    int row,
    List<List<Object?>> values,
  ) {
    final rows = books[id]![title]!;
    for (var i = 0; i < values.length; i++) {
      while (rows.length < row + i) {
        rows.add([]);
      }
      final r = rows[row - 1 + i];
      for (var j = 0; j < values[i].length; j++) {
        while (r.length <= col + j) {
          r.add('');
        }
        final v = values[i][j];
        r[col + j] =
            v is double && v == v.truncateToDouble()
                ? '${v.toInt()}'
                : '${v ?? ''}';
      }
    }
  }

  @override
  Future<String?> valuesUpdate(
    String id,
    String range,
    List<List<Object?>> values,
  ) async {
    log.add('UPDATE $id $range (${values.length} rows)');
    final (title, col, row, _) = _range(range);
    _write(id, title, columnLetterToIndex(col)!, row, values);
    return range;
  }

  @override
  Future<String?> valuesAppend(
    String id,
    String range,
    List<List<Object?>> values,
  ) async {
    log.add('APPEND $id $range (${values.length} rows)');
    final (title, _, _, _) = _range(range);
    final rows = books[id]![title]!;
    final start = rows.length + 1;
    _write(id, title, 0, start, values);
    return "'$title'!A$start:ZZ${start + values.length - 1}";
  }

  @override
  Future<List<Map<String, dynamic>>> batchUpdate(
    String id,
    List<Map<String, dynamic>> requests,
  ) async {
    log.add(
      'BATCH $id ${requests.length} [${requests.map((r) => r.keys.first).toSet().join(',')}]',
    );
    final replies = <Map<String, dynamic>>[];
    for (final r in requests) {
      if (r['addSheet'] != null) {
        final t = r['addSheet']['properties']['title'] as String;
        if (books[id]!.keys.any((k) => k.toLowerCase() == t.toLowerCase())) {
          throw SheetsApiException(
            'A sheet with the name "$t" already exists.',
            status: 400,
          );
        }
        add(id, t, []);
        replies.add({
          'addSheet': {
            'properties': {'sheetId': ids[id]![t], 'title': t},
          },
        });
      } else if (r['repeatCell'] != null) {
        final range = r['repeatCell']['range'];
        final c =
            r['repeatCell']['cell']['userEnteredFormat']['backgroundColor']
                as Map;
        final hex =
            '#${[c['red'], c['green'], c['blue']].map((v) => ((v as num) * 255).round().toRadixString(16).padLeft(2, '0')).join()}';
        colors.putIfAbsent(
              '$id|${range['sheetId']}',
              () => {},
            )[range['startRowIndex'] as int] =
            hex;
        replies.add({});
      }
    }
    return replies;
  }

  @override
  Future<String> createSpreadsheet(
    String title,
    List<String> sheetTitles,
  ) async {
    final id = 'new${_next++}';
    log.add('CREATE "$title" -> $id');
    books[id] = {};
    ids[id] = {};
    for (final t in sheetTitles) {
      add(id, t, []);
    }
    return id;
  }
}
