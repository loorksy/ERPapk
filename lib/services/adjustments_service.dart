import '../data/app_database.dart';
import '../erp/js_compat.dart';
import '../erp/normalize.dart';
import '../erp/payroll_audit_engine.dart';
import '../google/sheets_client.dart';

/// «إضافات وخصومات» — port of ERP `services/memberAdjustmentSheetOps.js`
/// (bulk only, without the advanced accounting registration, owner's
/// decision 2026-11-17). Separate from the audit.
///
/// ERP reads the sheet, then for each pasted line (id, type, amount) finds
/// the user's first row and applies `computeSheetOp` to its salary, writing
/// the new salary and a status text in the chosen columns. Lines are applied
/// in order on the updated salary.
///
/// Owner's change: when one user has both additions and deductions in the
/// list, they are first netted into one settlement (تسوية) at the place of
/// the user's first line, and the status cell says what was done (تم خصم /
/// تم اضافة) followed by the settlement. «خصم كامل» lines are not netted.
///
/// The app computes everything first (same values as ERP's line-by-line
/// writes) and writes the final cells in batches, as a resumable job.
class AdjustmentsService {
  AdjustmentsService(this.db, this.sheetsProvider);

  final AppDatabase db;
  final SheetsApi Function() sheetsProvider;

  /// ERP defaults of the page (`DEFAULT_COLS`).
  static const defaultIdCol = 'C';
  static const defaultSalaryCol = 'L';
  static const defaultStatusCol = 'O';

  static const cellsPerRequest = 2000;

  Future<AdjustPlan> prepare(
    AdjustRequest req,
    void Function(String) progress,
  ) async {
    final ssId = req.spreadsheetId.trim();
    final title = req.sheetName.trim();
    if (ssId.isEmpty) return AdjustPlan.fail('اختر ملف جدول البيانات');
    if (title.isEmpty) return AdjustPlan.fail('اختر الورقة المطلوبة');
    final uidCol = columnLetterToIndex(req.idCol) ?? 2;
    final salCol = columnLetterToIndex(req.salaryCol) ?? 11;
    final stCol = columnLetterToIndex(req.statusCol) ?? 14;
    if (salCol == stCol || salCol == uidCol || stCol == uidCol) {
      return AdjustPlan.fail('أعمدة ID والراتب والحالة يجب أن تكون مختلفة.');
    }
    final sheets = sheetsProvider();
    progress('قراءة الورقة «$title»...');
    final meta = await withSheetsRetry(() => sheets.getSpreadsheet(ssId));
    // ERP reads from row 1 in batches; with the grid size no rows are lost
    // after a gap on a batch edge (same fix as the audit).
    final rows = await fetchSheetValuesBatched(
      sheets,
      ssId,
      title,
      rowCount: sheetRowCount(meta, title),
    );
    final computed = computeBulk(
      req.bulkData,
      rows,
      uidCol: uidCol,
      salCol: salCol,
      stCol: stCol,
    );
    final esc = escapeSheetTitleForRange(title);
    final salLetter = columnIndexToLetter(salCol);
    final stLetter = columnIndexToLetter(stCol);
    final rowsOut = [
      for (final w in computed.writes)
        [w.row, w.originalSalary, w.salary, w.status],
    ];
    final steps = <Map<String, Object?>>[];
    if (rowsOut.isNotEmpty) {
      steps.add({
        'k': 'adjCheck',
        'ss': ssId,
        'range': "'$esc'!$salLetter",
        'rows': rowsOut,
      });
      final perStep = cellsPerRequest ~/ 2;
      for (var i = 0; i < rowsOut.length; i += perStep) {
        steps.add({
          'k': 'adjWrite',
          'ss': ssId,
          'sheet': esc,
          'sal': salLetter,
          'st': stLetter,
          'rows': rowsOut.sublist(
            i,
            i + perStep > rowsOut.length ? rowsOut.length : i + perStep,
          ),
        });
      }
    }
    return AdjustPlan(
      steps: steps,
      next: 0,
      result: AdjustOutcome(
        success: true,
        message:
            computed.results.isEmpty
                ? 'لم تُقرأ أي أسطر صالحة (رقم ← نوع ← مبلغ).'
                : 'تمت معالجة ${computed.results.length} عملية',
        results: computed.results,
        summary: summarize(computed.results),
        spreadsheetUrl: meta.url,
      ),
    );
  }

  /// Runs step [index]; repeating a step writes the same cells again.
  Future<void> runStep(
    AdjustPlan plan,
    int index,
    void Function(String) progress,
  ) async {
    final step = plan.steps[index];
    final sheets = sheetsProvider();
    final rows = [
      for (final r in (step['rows'] as List))
        (r as List).map((e) => e?.toString() ?? '').toList(),
    ];
    if (step['k'] == 'adjCheck') {
      progress('التحقق من أن الرواتب لم تتغير...');
      await _check(sheets, step['ss'] as String, step['range'] as String, rows);
      return;
    }
    progress('كتابة ${rows.length} صف...');
    final sheet = step['sheet'] as String;
    await withSheetsRetry(
      () => sheets.valuesBatchUpdate(step['ss'] as String, [
        for (final r in rows) ...[
          (
            "'$sheet'!${step['sal']}${r[0]}",
            [
              [r[2]],
            ],
          ),
          (
            "'$sheet'!${step['st']}${r[0]}",
            [
              [r[3]],
            ],
          ),
        ],
      ]),
    );
  }

  /// Stops before writing if someone changed a salary since the sheet was
  /// read (a job may wait hours for the internet): the computed values would
  /// be applied twice otherwise. Cells already written by this job pass.
  Future<void> _check(
    SheetsApi sheets,
    String ss,
    String range,
    List<List<String>> rows,
  ) async {
    var first = rows.first[0], last = rows.first[0];
    for (final r in rows) {
      if (int.parse(r[0]) < int.parse(first)) first = r[0];
      if (int.parse(r[0]) > int.parse(last)) last = r[0];
    }
    final m = RegExp(r"^(.*)!([A-Z]+)$").firstMatch(range)!;
    final values = await withSheetsRetry(
      () => sheets.valuesGet(
        ss,
        '${m.group(1)}!${m.group(2)}$first:${m.group(2)}$last',
      ),
    );
    final start = int.parse(first);
    for (final r in rows) {
      final i = int.parse(r[0]) - start;
      final now = i < values.length && values[i].isNotEmpty ? values[i][0] : '';
      final cur = round2(parseSalaryCellNumber(now));
      if (cur != round2(parseSalaryCellNumber(r[1])) &&
          cur != round2(parseSalaryCellNumber(r[2]))) {
        throw AdjustmentConflict(
          'تغيّر الراتب في الصف ${r[0]} بعد قراءة الورقة. لم يُكتب شيء؛ أعد معالجة القائمة.',
        );
      }
    }
  }

  // ======================================================================
  // ERP logic (memberAdjustmentSheetOps.js)
  // ======================================================================

  /// ERP `round2`: `Math.round((parseFloat(num) || 0) * 100) / 100`.
  static double round2(Object? value) {
    final double n;
    if (value is num) {
      n = value.toDouble();
    } else {
      n = jsParseFloat(value?.toString() ?? '');
    }
    final v = n.isNaN || n == 0 ? 0.0 : n;
    return jsRound(v * 100) / 100;
  }

  /// ERP `parseLocaleDecimal` (payrollSearchService.js).
  static double parseLocaleDecimal(Object? val) {
    if (val == null || val == '') return double.nan;
    if (val is num) return val.isFinite ? val.toDouble() : double.nan;
    var s =
        val
            .toString()
            .replaceAll(
              RegExp('[\u200B-\u200D\u2060\uFEFF\u200E\u200F\u202A-\u202E]'),
              '',
            )
            .trim();
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    s = s
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(r'$', '')
        .replaceAll(RegExp('USD', caseSensitive: false), '');
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    if (lastComma >= 0 && lastDot < 0) {
      final parts = s.split(',');
      // ERP's regex /^\d*$\.?\d*$/ only matches digits.
      if (parts.length == 2 &&
          parts[1].length <= 2 &&
          RegExp(r'^\d*$').hasMatch(parts[0])) {
        s = '${parts[0]}.${parts[1]}';
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (lastDot >= 0 && lastComma >= 0) {
      if (lastDot > lastComma) {
        s = s.replaceAll(',', '');
      } else {
        s = s.replaceAll('.', '').replaceFirst(',', '.');
      }
    } else {
      s = s.replaceAll(',', '');
    }
    final n = jsParseFloat(s);
    return n.isNaN || !n.isFinite ? double.nan : n;
  }

  /// ERP `parseSalaryCellNumber`.
  static double parseSalaryCellNumber(Object? v) {
    final n = parseLocaleDecimal(v);
    return n.isFinite ? n : 0;
  }

  /// ERP `computeSheetOp`.
  static SheetOp computeSheetOp({
    required double currentSalary,
    required String type,
    required String? amountRaw,
  }) {
    final typeStr = type.trim();
    final amountStr = amountRaw == null ? '' : amountRaw.trim();
    final isFullDeduction =
        typeStr.contains('خصم كامل') || amountStr.contains('خصم كامل');
    var amountNum = 0.0;
    if (!isFullDeduction) amountNum = round2(amountStr.replaceFirst(',', '.'));

    final cur = round2(currentSalary);
    var status = 'تم التحديث';
    var displayed = amountNum;
    var added = 0.0, deducted = 0.0, debt = 0.0, zeroSalAmt = 0.0;
    var newSalary = cur;
    var statusText = '';
    final amt = jsNumberToString(amountNum);

    if (isFullDeduction || typeStr == 'خصم') {
      if (isFullDeduction) {
        deducted = cur > 0 ? cur : 0;
        status = 'تم خصم الدين';
        displayed = deducted;
        newSalary = 0;
        statusText = 'تم خصم الدين';
      } else {
        if (cur <= 0) {
          debt = 0;
          zeroSalAmt = amountNum;
          status = 'سحب ادارة';
          displayed = amountNum;
          newSalary = 0;
        } else if (cur < amountNum) {
          debt = round2(amountNum - cur);
          if (debt < 1) {
            debt = 0;
            deducted = cur;
            status = 'تم الخصم بالكامل';
            displayed = amountNum;
          } else {
            deducted = cur;
            status = 'باقي عليه';
            displayed = debt;
          }
          newSalary = 0;
        } else {
          deducted = amountNum;
          newSalary = round2(cur - amountNum);
          status = 'تم الخصم بالكامل';
        }
        statusText = 'تم خصم $amt';
      }
    } else {
      // إضافة (أو أي نوع غير الخصم)
      added = amountNum;
      newSalary = round2(cur + amountNum);
      status = 'تمت الإضافة';
      statusText = 'تم اضافة $amt';
    }
    return SheetOp(
      AdjustResult(
        id: '',
        status: status,
        amount: displayed,
        added: added,
        deducted: deducted,
        debt: debt,
        zeroSalAmt: zeroSalAmt,
      ),
      newSalary,
      statusText,
      amountNum,
      isFullDeduction,
    );
  }

  /// ERP's line parsing in `processSheetBulk`: Tab-separated (or spaces)
  /// id, type, amount; «خصم كامل» needs no amount.
  static List<AdjustLine> parseLines(String bulkData) {
    final out = <AdjustLine>[];
    for (final line in bulkData.split('\n')) {
      if (line.trim().isEmpty) continue;
      var parts = line.split('\t');
      if (parts.length < 2) parts = line.trim().split(RegExp(r'\s{2,}|\s+'));
      if (parts.length < 2) continue;
      final userId = parts[0].trim();
      final type = parts[1].trim();
      var full = type.contains('خصم كامل');
      var amountNum = 0.0;
      var amountRaw = '';
      if (parts.length >= 3) {
        amountRaw = parts[2].trim();
        if (amountRaw.contains('خصم كامل')) {
          full = true;
        } else if (!full) {
          amountNum = round2(amountRaw.replaceFirst(',', '.'));
        }
      }
      if (!full && parts.length < 3) continue;
      out.add(AdjustLine(userId, type, amountRaw, full, amountNum));
    }
    return out;
  }

  /// ERP `processSheetBulk` on rows already read, with the owner's
  /// settlement. Returns the results (ERP order) and the final cells.
  /// [settle] false gives ERP's exact line-by-line result (used to check
  /// the port against ERP's JavaScript).
  static BulkComputation computeBulk(
    String bulkData,
    List<List<String>> rows, {
    int uidCol = 2,
    int salCol = 11,
    int stCol = 14,
    bool settle = true,
  }) {
    final dataStart =
        rows.isNotEmpty && isHeaderRowUserInfo(rows[0], uidCol) ? 1 : 0;
    final index = <String, int>{};
    for (var i = dataStart; i < rows.length; i++) {
      final raw = cellAt(rows[i], uidCol);
      final n = normalizeUserId(raw);
      final key = n.isNotEmpty ? n : (raw ?? '').trim();
      if (key.isNotEmpty && !index.containsKey(key)) index[key] = i;
    }
    int? rowOf(String userId) {
      final n = normalizeUserId(userId);
      return index[n.isNotEmpty ? n : userId];
    }

    // Owner's settlement: additions and deductions of one user are netted
    // into one operation at the place of the user's first such line.
    final lines = parseLines(bulkData);
    final ops = <_Op>[];
    final settled = <int, _Op>{};
    final byRow = <int, List<AdjustLine>>{};
    for (final l in lines) {
      final r = rowOf(l.userId);
      if (r != null && !l.full) byRow.putIfAbsent(r, () => []).add(l);
    }
    for (final l in lines) {
      final r = rowOf(l.userId);
      final mine = r == null ? null : byRow[r];
      final mixed =
          settle &&
          mine != null &&
          mine.any((x) => x.isDeduction) &&
          mine.any((x) => !x.isDeduction);
      if (!l.full && mixed) {
        if (settled.containsKey(r)) continue; // merged into the first line
        var add = 0.0, ded = 0.0;
        for (final x in mine) {
          if (x.isDeduction) {
            ded += x.amountNum;
          } else {
            add += x.amountNum;
          }
        }
        final op = _Op(l, r, round2(add), round2(ded));
        settled[r!] = op;
        ops.add(op);
      } else {
        ops.add(_Op(l, r, null, null));
      }
    }

    final results = <AdjustResult>[];
    final salaryNow = <int, double>{};
    final finalCells = <int, AdjustWrite>{};
    for (final op in ops) {
      final l = op.line;
      final found = op.row;
      if (found == null) {
        final amt = l.full ? 0.0 : l.amountNum;
        results.add(
          AdjustResult(
            id: l.userId,
            status: 'غير موجود',
            amount: amt,
            notFoundAmt: amt,
          ),
        );
        continue;
      }
      final current =
          salaryNow[found] ??
          parseSalaryCellNumber(cellAt(rows[found], salCol));
      SheetOp computed;
      String? settlement;
      if (op.isSettlement) {
        final net = round2(op.add! - op.ded!);
        settlement =
            'إضافة ${jsNumberToString(op.add!)}، خصم ${jsNumberToString(op.ded!)}';
        if (net == 0) {
          computed = SheetOp(
            AdjustResult(id: '', status: 'تمت التسوية', amount: 0),
            round2(current),
            'تمت التسوية',
            0,
            false,
          );
        } else {
          computed = computeSheetOp(
            currentSalary: current,
            type: net < 0 ? 'خصم' : 'اضافة',
            amountRaw: jsNumberToString(net.abs()),
          );
        }
      } else {
        computed = computeSheetOp(
          currentSalary: current,
          type: l.full ? 'خصم كامل' : l.type,
          amountRaw: l.full ? 'خصم كامل' : l.amountRaw,
        );
      }
      final statusText =
          settlement == null
              ? computed.statusText
              : computed.statusText == 'تمت التسوية'
              ? 'تمت التسوية ($settlement)'
              : '${computed.statusText} (تسوية: $settlement)';
      salaryNow[found] = computed.newSalary;
      final prev = finalCells[found];
      finalCells[found] = AdjustWrite(
        row: found + 1,
        originalSalary:
            prev?.originalSalary ?? (cellAt(rows[found], salCol) ?? ''),
        salary: round2(computed.newSalary).toStringAsFixed(2),
        status: statusText,
      );
      results.add(
        computed.result.copyWith(id: l.userId, settlement: settlement),
      );
    }
    final writes = finalCells.values.toList()..sort((a, b) => a.row - b.row);
    return BulkComputation(results, writes);
  }

  /// ERP `summarizeResults`.
  static AdjustSummary summarize(List<AdjustResult> results) {
    var added = 0.0, deducted = 0.0, debt = 0.0, notFound = 0.0;
    final debtUsers = <String>[];
    for (final r in results) {
      added += r.added;
      deducted += r.deducted;
      debt += r.debt;
      notFound += r.notFoundAmt + r.zeroSalAmt;
      if (r.debt > 0) debtUsers.add(r.id);
    }
    return AdjustSummary(
      totalAdded: round2(added),
      totalDeducted: round2(deducted),
      totalDebt: round2(debt),
      totalNotFound: round2(notFound),
      debtUsers: debtUsers,
    );
  }

  /// ERP `formatMoneyUI`.
  static String money(double v) => '\$${jsNumberToString(round2(v))}';

  /// ERP `copyTableToSheet`: the table and the totals as Tab-separated text.
  static String copyText(List<AdjustResult> results, AdjustSummary s) {
    String m(double v) => money(v).replaceFirst('.', ',');
    final b = StringBuffer('رقم المستخدم\tالحالة\tالمبلغ\n');
    for (final r in results) {
      b.write('${r.id}\t${r.displayStatus}\t${m(r.amount)}\n');
    }
    b.write('\n');
    b.write('مجموع المتبقي (لنا عليهم)\t\t${m(s.totalDebt)}\n');
    b.write('مجموع تم خصم\t\t${m(s.totalDeducted)}\n');
    b.write('مجموع غير موجود\t\t${m(s.totalNotFound)}\n');
    return b.toString();
  }
}

class AdjustmentConflict implements Exception {
  const AdjustmentConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdjustRequest {
  const AdjustRequest({
    required this.spreadsheetId,
    required this.sheetName,
    required this.bulkData,
    this.idCol = AdjustmentsService.defaultIdCol,
    this.salaryCol = AdjustmentsService.defaultSalaryCol,
    this.statusCol = AdjustmentsService.defaultStatusCol,
  });
  final String spreadsheetId;
  final String sheetName;
  final String idCol;
  final String salaryCol;
  final String statusCol;
  final String bulkData;

  Map<String, Object?> toJson() => {
    'kind': 'adjustments',
    'spreadsheetId': spreadsheetId,
    'sheetName': sheetName,
    'idCol': idCol,
    'salaryCol': salaryCol,
    'statusCol': statusCol,
    'bulkData': bulkData,
  };

  static AdjustRequest fromJson(Map<String, Object?> j) => AdjustRequest(
    spreadsheetId: (j['spreadsheetId'] ?? '').toString(),
    sheetName: (j['sheetName'] ?? '').toString(),
    bulkData: (j['bulkData'] ?? '').toString(),
    idCol: (j['idCol'] as String?) ?? AdjustmentsService.defaultIdCol,
    salaryCol:
        (j['salaryCol'] as String?) ?? AdjustmentsService.defaultSalaryCol,
    statusCol:
        (j['statusCol'] as String?) ?? AdjustmentsService.defaultStatusCol,
  );
}

class AdjustLine {
  const AdjustLine(
    this.userId,
    this.type,
    this.amountRaw,
    this.full,
    this.amountNum,
  );
  final String userId;
  final String type;
  final String amountRaw;
  final bool full;
  final double amountNum;

  /// ERP: only the exact type «خصم» deducts; any other type adds.
  bool get isDeduction => !full && type == 'خصم';
}

class _Op {
  _Op(this.line, this.row, this.add, this.ded);
  final AdjustLine line;
  final int? row;
  final double? add;
  final double? ded;
  bool get isSettlement => add != null;
}

class SheetOp {
  const SheetOp(
    this.result,
    this.newSalary,
    this.statusText,
    this.amountNum,
    this.isFullDeduction,
  );
  final AdjustResult result;
  final double newSalary;
  final String statusText;
  final double amountNum;
  final bool isFullDeduction;
}

class AdjustWrite {
  const AdjustWrite({
    required this.row,
    required this.originalSalary,
    required this.salary,
    required this.status,
  });

  /// 1-based sheet row.
  final int row;
  final String originalSalary;
  final String salary;
  final String status;
}

class BulkComputation {
  const BulkComputation(this.results, this.writes);
  final List<AdjustResult> results;
  final List<AdjustWrite> writes;
}

/// One line of ERP's results table.
class AdjustResult {
  const AdjustResult({
    required this.id,
    required this.status,
    required this.amount,
    this.added = 0,
    this.deducted = 0,
    this.debt = 0,
    this.notFoundAmt = 0,
    this.zeroSalAmt = 0,
    this.settlement,
  });
  final String id;
  final String status;
  final double amount;
  final double added;
  final double deducted;
  final double debt;
  final double notFoundAmt;
  final double zeroSalAmt;

  /// «إضافة X، خصم Y» when the line is the owner's settlement.
  final String? settlement;

  String get displayStatus =>
      settlement == null || status == 'تمت التسوية'
          ? status
          : '$status (تسوية)';

  AdjustResult copyWith({required String id, String? settlement}) =>
      AdjustResult(
        id: id,
        status: status,
        amount: amount,
        added: added,
        deducted: deducted,
        debt: debt,
        notFoundAmt: notFoundAmt,
        zeroSalAmt: zeroSalAmt,
        settlement: settlement,
      );

  List<Object?> toJson() => [
    id,
    status,
    amount,
    added,
    deducted,
    debt,
    notFoundAmt,
    zeroSalAmt,
    settlement,
  ];

  static AdjustResult fromJson(Object? j) {
    final l = j as List;
    double d(int i) => (l[i] as num).toDouble();
    return AdjustResult(
      id: l[0].toString(),
      status: l[1].toString(),
      amount: d(2),
      added: d(3),
      deducted: d(4),
      debt: d(5),
      notFoundAmt: d(6),
      zeroSalAmt: d(7),
      settlement: l.length > 8 ? l[8] as String? : null,
    );
  }
}

class AdjustSummary {
  const AdjustSummary({
    required this.totalAdded,
    required this.totalDeducted,
    required this.totalDebt,
    required this.totalNotFound,
    required this.debtUsers,
  });
  final double totalAdded;
  final double totalDeducted;
  final double totalDebt;
  final double totalNotFound;
  final List<String> debtUsers;

  Map<String, Object?> toJson() => {
    'totalAdded': totalAdded,
    'totalDeducted': totalDeducted,
    'totalDebt': totalDebt,
    'totalNotFound': totalNotFound,
    'debtUsers': debtUsers,
  };

  static AdjustSummary fromJson(Map<String, Object?> j) => AdjustSummary(
    totalAdded: (j['totalAdded'] as num?)?.toDouble() ?? 0,
    totalDeducted: (j['totalDeducted'] as num?)?.toDouble() ?? 0,
    totalDebt: (j['totalDebt'] as num?)?.toDouble() ?? 0,
    totalNotFound: (j['totalNotFound'] as num?)?.toDouble() ?? 0,
    debtUsers: [
      for (final x in (j['debtUsers'] as List? ?? const [])) x.toString(),
    ],
  );
}

class AdjustOutcome {
  const AdjustOutcome({
    required this.success,
    required this.message,
    this.results = const [],
    this.summary,
    this.spreadsheetUrl,
  });
  final bool success;
  final String message;
  final List<AdjustResult> results;
  final AdjustSummary? summary;
  final String? spreadsheetUrl;

  Map<String, Object?> toJson() => {
    'kind': 'adjustments',
    'success': success,
    'message': message,
    'results': [for (final r in results) r.toJson()],
    'summary': summary?.toJson(),
    'spreadsheetUrl': spreadsheetUrl,
  };

  static AdjustOutcome fromJson(Map<String, Object?> j) => AdjustOutcome(
    success: j['success'] == true,
    message: (j['message'] ?? '').toString(),
    results: [
      for (final r in (j['results'] as List? ?? const []))
        AdjustResult.fromJson(r),
    ],
    summary:
        j['summary'] is Map
            ? AdjustSummary.fromJson(
              Map<String, Object?>.from(j['summary'] as Map),
            )
            : null,
    spreadsheetUrl: j['spreadsheetUrl'] as String?,
  );
}

class AdjustPlan {
  AdjustPlan({required this.steps, required this.next, required this.result})
    : failure = null;
  AdjustPlan.fail(String message)
    : steps = const [],
      next = 0,
      result = AdjustOutcome(success: false, message: message),
      failure = message;

  final List<Map<String, Object?>> steps;
  int next;
  final AdjustOutcome result;

  /// Set when the list cannot be processed (nothing is written).
  final String? failure;

  bool get complete => next >= steps.length;

  Map<String, Object?> toJson() => {
    'steps': steps,
    'next': next,
    'result': result.toJson(),
  };

  static AdjustPlan fromJson(Map<String, Object?> j) => AdjustPlan(
    steps: [
      for (final s in (j['steps'] as List)) Map<String, Object?>.from(s as Map),
    ],
    next: (j['next'] as num).toInt(),
    result: AdjustOutcome.fromJson(
      Map<String, Object?>.from(j['result'] as Map),
    ),
  );
}
