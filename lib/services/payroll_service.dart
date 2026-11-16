import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/app_database.dart';
import '../erp/js_compat.dart';
import '../erp/normalize.dart';
import '../erp/payroll_audit_engine.dart';
import '../google/sheets_client.dart';

typedef Progress = void Function(String message);

/// Where the user-info table ("جدول معلومات المستخدمين") comes from.
sealed class UserInfoSource {
  const UserInfoSource();
}

class GoogleUserInfo extends UserInfoSource {
  const GoogleUserInfo(this.spreadsheetId, this.sheetName);
  final String spreadsheetId;

  /// Empty → first sheet (ERP «أول ورقة»).
  final String? sheetName;
}

class LocalUserInfo extends UserInfoSource {
  const LocalUserInfo(this.fileName, this.sheetName, this.rows);
  final String fileName;
  final String sheetName;
  final Rows rows;
}

class PayrollRequest {
  const PayrollRequest({
    required this.cycleId,
    required this.userInfo,
    required this.discountRate,
    required this.agentColor,
    required this.managementColor,
    required this.columns,
    this.userInfoStatusCol,
    this.forceReaudit = false,
  });

  final int cycleId;
  final UserInfoSource userInfo;

  /// `null` → saved settings (ERP `resolvePayrollDiscountRatePct`).
  final double? discountRate;
  final String agentColor;
  final String managementColor;
  final AuditColumns columns;
  final String? userInfoStatusCol;
  final bool forceReaudit;
}

class SampleCheck {
  const SampleCheck(this.userId, this.inMgmt, this.inAgent);
  final String userId;
  final bool inMgmt;
  final bool inAgent;
}

class PayrollDiagnostic {
  const PayrollDiagnostic({
    required this.managementUniqueCount,
    required this.agentUniqueCount,
    required this.userInfoUniqueCount,
    required this.sampleCheck,
  });
  final int managementUniqueCount;
  final int agentUniqueCount;
  final int userInfoUniqueCount;
  final List<SampleCheck> sampleCheck;
}

class PayrollResult {
  PayrollResult({
    required this.success,
    required this.message,
    this.code,
    this.summary,
    this.applied = false,
    this.cycleSynced = false,
    this.localOnly = false,
    this.spreadsheetUrl,
    this.results = const [],
    this.sampleUserIds = const [],
    this.sampleMgmtIds = const [],
    this.sampleAgentIds = const [],
    this.diagnostic,
    this.duplicateRowNumbers = const [],
  });

  factory PayrollResult.fail(
    String message, {
    String? code,
    String? url,
    List<int> rows = const [],
  }) => PayrollResult(
    success: false,
    message: message,
    code: code,
    spreadsheetUrl: url,
    duplicateRowNumbers: rows,
  );

  final bool success;
  final String message;
  final String? code;
  final AuditSummary? summary;
  final bool applied;
  final bool cycleSynced;
  final bool localOnly;
  final String? spreadsheetUrl;
  final List<AuditResultRow> results;
  final List<String> sampleUserIds;
  final List<String> sampleMgmtIds;
  final List<String> sampleAgentIds;
  final PayrollDiagnostic? diagnostic;
  final List<int> duplicateRowNumbers;

  bool get unchanged => code == 'USER_INFO_UNCHANGED';

  Map<String, Object?> toLog() => {
    'success': success,
    'message': message,
    'summary': summary?.toJson(),
    'localOnly': localOnly,
    'spreadsheetUrl': spreadsheetUrl,
  };
}

/// ERP `hashUserInfoRows`.
String hashUserInfoRows(Rows rows) =>
    sha256.convert(utf8.encode(jsonEncode(rows))).toString();

/// ERP `resolvePayrollDiscountRatePct`.
double resolveDiscount(double? requested, PayrollSettings settings) {
  if (requested == null || requested.isNaN) return settings.discountRate;
  return requested;
}

/// The bulk audit — a port of ERP `POST /api/sheet/payroll-execute`
/// running on the phone. Accounting side effects of ERP (sub-agency sync,
/// cash box, deferred salaries, profit ledger) are ERP-database features
/// and are not part of the audit app.
class PayrollService {
  PayrollService(this.db, this.sheetsProvider);

  final AppDatabase db;

  /// Returns the Google client, or throws when the account is not connected.
  final SheetsApi Function() sheetsProvider;

  Future<PayrollResult> execute(
    PayrollRequest req, {
    Progress? onProgress,
  }) async {
    try {
      return switch (req.userInfo) {
        GoogleUserInfo g => await _executeGoogle(req, g, onProgress ?? (_) {}),
        LocalUserInfo l => await _executeLocal(req, l, onProgress ?? (_) {}),
      };
    } on SheetsApiException catch (e) {
      return PayrollResult.fail(e.message);
    } catch (e) {
      return PayrollResult.fail(
        e.toString().isEmpty ? 'فشل تنفيذ التدقيق' : e.toString(),
      );
    }
  }

  // ======================================================================
  // Google mode (identical to ERP payroll-execute)
  // ======================================================================

  Future<PayrollResult> _executeGoogle(
    PayrollRequest req,
    GoogleUserInfo ui,
    Progress progress,
  ) async {
    final settings = await db.getPayrollSettings();
    final discountRatePct = resolveDiscount(req.discountRate, settings);
    final cycle = await db.getCycle(req.cycleId);
    if (cycle == null) return PayrollResult.fail('الدورة المالية غير موجودة');

    final sheets = sheetsProvider();
    var managementRows = cycle.managementRows;
    var agentRows = cycle.agentRows;
    final mgmtSsId = cycle.managementSpreadsheetId;
    final mgmtSheetName = cycle.managementSheetName;
    final agentSsId = cycle.agentSpreadsheetId;
    final agentSheetNameCycle = cycle.agentSheetName;

    var cycleSynced = false;
    if (mgmtSsId != null && agentSsId != null) {
      progress('1/2 مزامنة جداول الدورة من Google...');
      try {
        final mgmtResult = await fetchSheetWithFallback(
          sheets,
          mgmtSsId,
          mgmtSheetName,
        );
        final agentResult = await fetchSheetWithFallback(
          sheets,
          agentSsId,
          agentSheetNameCycle,
          mgmtSsId == agentSsId ? mgmtResult.sheetTitleUsed : null,
        );
        managementRows = mgmtResult.values;
        agentRows = agentResult.values;
        await db.updateCycle(cycle.id, {
          'management_data': managementRows,
          'agent_data': agentRows,
          'management_sheet_name': mgmtResult.sheetTitleUsed ?? mgmtSheetName,
          'agent_sheet_name': agentResult.sheetTitleUsed ?? agentSheetNameCycle,
        });
        cycleSynced = true;
      } catch (_) {
        // ERP continues with the saved snapshots when the sync fails.
      }
    }

    progress('1/2 قراءة جدول معلومات المستخدمين...');
    final spreadsheetId = ui.spreadsheetId;
    final meta = await withSheetsRetry(
      () => sheets.getSpreadsheet(spreadsheetId),
    );
    final firstSheet = meta.sheets.isEmpty ? null : meta.sheets.first;
    final requestedTitle = ui.sheetName?.trim() ?? '';
    final mainSheetTitle =
        requestedTitle.isNotEmpty
            ? requestedTitle
            : (firstSheet?.title ?? 'Sheet1');
    final allRows = await withSheetsRetry(
      () => sheets.valuesGet(spreadsheetId, rangeWholeSheet(mainSheetTitle)),
    );
    final spreadsheetUrl = meta.url;

    final dupCheck = findDuplicateUserInfoMemberIds(
      allRows,
      req.columns.userInfoUserIdCol,
    );
    if (dupCheck.duplicateIds.isNotEmpty) {
      return PayrollResult.fail(
        _duplicateMessage(dupCheck.duplicateRowNumbers),
        code: 'USER_INFO_DUPLICATE_IDS',
        url: spreadsheetUrl,
        rows: dupCheck.duplicateRowNumbers,
      );
    }
    final userInfoHash = hashUserInfoRows(allRows);
    if (cycle.userInfoHash != null &&
        cycle.userInfoHash == userInfoHash &&
        !req.forceReaudit) {
      return PayrollResult.fail(
        'لم يتغيّر جدول معلومات المستخدمين من آخر تدقيق ناجح. عدّل الجدول ثم أعد المحاولة.',
        code: 'USER_INFO_UNCHANGED',
        url: spreadsheetUrl,
      );
    }

    final out = runPayrollAuditCore(
      managementRows: managementRows,
      agentRows: agentRows,
      userInfoRows: allRows,
      columns: req.columns,
      discountRatePct: discountRatePct,
      agentColor: req.agentColor,
      managementColor: req.managementColor,
    );
    final cycleMgmtCol = out.cycleMgmtCol;

    var cycleMgmtSsId = mgmtSsId;
    var cycleAgentSsId = agentSsId;
    var cycleMgmtSheetName = mgmtSheetName;
    var cycleAgentSheetName = agentSheetNameCycle;

    progress('2/2 تطبيق النتائج على Google...');
    // A cycle built from uploaded files gets its own Google spreadsheet,
    // exactly like ERP.
    if (cycleMgmtSsId == null || cycleAgentSsId == null) {
      final cycleName = cycle.name.trim().isEmpty ? 'دورة' : cycle.name.trim();
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final newId = await withSheetsRetry(
        () => sheets.createSpreadsheet('دورة $cycleName - $dateStr', const [
          'الإدارة',
          'الوكيل',
        ]),
      );
      await withSheetsRetry(
        () => sheets.valuesUpdate(newId, "'الإدارة'!A1", managementRows),
      );
      await withSheetsRetry(
        () => sheets.valuesUpdate(newId, "'الوكيل'!A1", agentRows),
      );
      await db.updateCycle(cycle.id, {
        'management_spreadsheet_id': newId,
        'management_sheet_name': 'الإدارة',
        'agent_spreadsheet_id': newId,
        'agent_sheet_name': 'الوكيل',
      });
      cycleMgmtSsId = newId;
      cycleAgentSsId = newId;
      cycleMgmtSheetName = 'الإدارة';
      cycleAgentSheetName = 'الوكيل';
    }

    // Target sheet names from the title column (ERP column D).
    final titleToSheetName = <String, String>{};
    final usedNames = <String>{};
    for (final title in out.titleOrder) {
      var st = safeSheetTitle(title);
      while (usedNames.contains(st)) {
        st = '${st}_${usedNames.length}';
      }
      usedNames.add(st);
      titleToSheetName[title] = st;
    }
    var sheetNamesOrdered =
        out.titleOrder.map((t) => titleToSheetName[t]!).toList();
    final sheetIdByName = <String, int>{};
    var existingMgmtSheetTitles = <String>[];
    if (sheetNamesOrdered.isNotEmpty) {
      try {
        final metaMgmt = await withSheetsRetry(
          () => sheets.getSpreadsheet(cycleMgmtSsId!),
        );
        existingMgmtSheetTitles = [for (final s in metaMgmt.sheets) s.title];
        for (final st in sheetNamesOrdered) {
          for (final s in metaMgmt.sheets) {
            if (s.title == st) sheetIdByName[st] = s.sheetId;
          }
        }
        final seenLower = <String>{};
        sheetNamesOrdered = [
          for (final n in sheetNamesOrdered)
            if (seenLower.add(n.toLowerCase())) n,
        ];
      } catch (e) {
        throw Exception(
          'لا يمكن الوصول إلى جدول الإدارة (الدورة). تأكد أن الدورة مرتبطة بجدول في حساب Google المرتبط بالتطبيق: $e',
        );
      }
    }
    final existingLower =
        existingMgmtSheetTitles.map((t) => t.toLowerCase()).toSet();
    final toCreate = <String>[];
    final toCreateLower = <String>{};
    for (final st in sheetNamesOrdered) {
      final lower = st.toLowerCase();
      if (existingLower.contains(lower) || !toCreateLower.add(lower)) continue;
      toCreate.add(st);
    }
    if (toCreate.isNotEmpty) {
      progress('2/2 إنشاء ${toCreate.length} ورقة في جدول الإدارة...');
      final replies = await withSheetsRetry(
        () => sheets.batchUpdate(cycleMgmtSsId!, [
          for (final st in toCreate)
            {
              'addSheet': {
                'properties': {'title': st},
              },
            },
        ]),
      );
      for (var i = 0; i < replies.length && i < toCreate.length; i++) {
        final props = (replies[i]['addSheet'] as Map?)?['properties'] as Map?;
        if (props != null && props['sheetId'] is num) {
          sheetIdByName[toCreate[i]] = (props['sheetId'] as num).toInt();
        }
      }
    }

    final auditedMemberIds = await db.auditedMemberIds(cycle.id);
    var sheetIter = 0;
    for (final title in out.titleOrder) {
      if (sheetIter > 0) await sleepMs(1200);
      sheetIter++;
      final sheetName = titleToSheetName[title]!;
      final items = out.byTitle[title] ?? const <TitleItem>[];
      if (items.isEmpty) continue;
      final sheetExisted = existingMgmtSheetTitles.contains(sheetName);

      final existingInSheetIds = <String>{};
      if (sheetExisted) {
        try {
          final sheetRows = await withSheetsRetry(
            () => sheets.valuesGet(cycleMgmtSsId!, rangeWholeSheet(sheetName)),
          );
          for (var idx = 0; idx < sheetRows.length; idx++) {
            final row = sheetRows[idx];
            if (idx == 0 && isHeaderRowGeneric(row, cycleMgmtCol)) continue;
            final id = normalizeUserId(cellAt(row, cycleMgmtCol));
            if (id.isNotEmpty) existingInSheetIds.add(id);
          }
        } catch (_) {}
      }
      final seenInBatch = <String>{};
      final itemsToPaste =
          items.where((it) {
            final id = normalizeUserId(cellAt(it.managementRow, cycleMgmtCol));
            if (id.isEmpty ||
                existingInSheetIds.contains(id) ||
                auditedMemberIds.contains(id)) {
              return false;
            }
            return seenInBatch.add(id);
          }).toList();
      if (itemsToPaste.isEmpty) continue;
      progress('2/2 نسخ ${itemsToPaste.length} صف إلى ورقة «$sheetName»...');
      final values = [for (final it in itemsToPaste) it.managementRow];
      try {
        if (sheetExisted) {
          await withSheetsRetry(
            () => sheets.valuesAppend(
              cycleMgmtSsId!,
              rangeWholeSheet(sheetName),
              values,
            ),
          );
        } else {
          await withSheetsRetry(
            () => sheets.valuesUpdate(
              cycleMgmtSsId!,
              "'${escapeSheetTitleForRange(sheetName)}'!A1",
              values,
            ),
          );
        }
      } catch (e) {
        throw Exception(
          'فشل نسخ الصفوف إلى ورقة «$sheetName» في جدول الإدارة: $e',
        );
      }
    }

    // Salary column and the aligned status column in the user-info sheet.
    final writes = _salaryStatusColumns(req, out);
    if (writes.salaryValues.isNotEmpty) {
      progress('2/2 كتابة الراتب والحالة في جدول معلومات المستخدمين...');
      final t = escapeSheetTitleForRange(mainSheetTitle);
      await withSheetsRetry(
        () => sheets.valuesUpdate(
          spreadsheetId,
          "'$t'!${writes.salaryColLetter}${writes.minRow}:${writes.salaryColLetter}${writes.maxRow}",
          writes.salaryValues,
        ),
      );
      await withSheetsRetry(
        () => sheets.valuesUpdate(
          spreadsheetId,
          "'$t'!${writes.statusColLetter}${writes.minRow}:${writes.statusColLetter}${writes.maxRow}",
          writes.statusValues,
        ),
      );
    }

    // Color the original management and agent rows.
    final colors = _sourceColors(out);
    if (colors.mgmt.isNotEmpty) {
      final metaMgmt = await withSheetsRetry(
        () => sheets.getSpreadsheet(cycleMgmtSsId!),
      );
      final mgmtSheetId = getSheetIdByTitle(metaMgmt, cycleMgmtSheetName);
      if (mgmtSheetId != null) {
        await batchUpdateRequestsInChunks(
          sheets,
          cycleMgmtSsId,
          _colorRequests(
            mgmtSheetId,
            colors.mgmt,
            colorEndColumn(metaMgmt, mgmtSheetId),
          ),
          onProgress: (d, t) => progress('2/2 تلوين صفوف الإدارة ($d/$t)...'),
        );
      }
    }
    if (colors.agent.isNotEmpty) {
      final metaAgent = await withSheetsRetry(
        () => sheets.getSpreadsheet(cycleAgentSsId!),
      );
      final agentSheetId = getSheetIdByTitle(metaAgent, cycleAgentSheetName);
      if (agentSheetId != null) {
        await batchUpdateRequestsInChunks(
          sheets,
          cycleAgentSsId,
          _colorRequests(
            agentSheetId,
            colors.agent,
            colorEndColumn(metaAgent, agentSheetId),
          ),
          onProgress: (d, t) => progress('2/2 تلوين صفوف الوكيل ($d/$t)...'),
        );
      }
    }

    final result = await _finish(
      cycle: cycle,
      out: out,
      managementRows: managementRows,
      agentRows: agentRows,
      cycleMgmtSheetName: cycleMgmtSheetName,
      cycleAgentSheetName: cycleAgentSheetName,
      userInfoHash: userInfoHash,
      spreadsheetUrl: spreadsheetUrl,
      cycleSynced: cycleSynced,
      localOnly: false,
    );
    await db.addAuditRun(cycle.id, 'google', result.toLog());
    return result;
  }

  // ======================================================================
  // Local mode: same audit, effects kept in a workbook on the phone
  // ======================================================================

  Future<PayrollResult> _executeLocal(
    PayrollRequest req,
    LocalUserInfo ui,
    Progress progress,
  ) async {
    final settings = await db.getPayrollSettings();
    final discountRatePct = resolveDiscount(req.discountRate, settings);
    final cycle = await db.getCycle(req.cycleId);
    if (cycle == null) return PayrollResult.fail('الدورة المالية غير موجودة');
    final managementRows = cycle.managementRows;
    final agentRows = cycle.agentRows;
    if (ui.rows.isEmpty) {
      return PayrollResult.fail('ملف معلومات المستخدمين فارغ.');
    }
    if (managementRows.isEmpty && agentRows.isEmpty) {
      return PayrollResult.fail(
        'بيانات الإدارة أو الوكيل فارغة. زامن الدورة أو أعد رفع الملفات.',
      );
    }
    progress('تدقيق على الهاتف...');
    final allRows = ui.rows;
    final dupCheck = findDuplicateUserInfoMemberIds(
      allRows,
      req.columns.userInfoUserIdCol,
    );
    if (dupCheck.duplicateIds.isNotEmpty) {
      return PayrollResult.fail(
        _duplicateMessage(dupCheck.duplicateRowNumbers),
        code: 'USER_INFO_DUPLICATE_IDS',
        rows: dupCheck.duplicateRowNumbers,
      );
    }
    final userInfoHash = hashUserInfoRows(allRows);
    if (cycle.userInfoHash != null &&
        cycle.userInfoHash == userInfoHash &&
        !req.forceReaudit) {
      return PayrollResult.fail(
        'لم يتغيّر جدول معلومات المستخدمين من آخر تدقيق ناجح. عدّل الملف ثم أعد المحاولة.',
        code: 'USER_INFO_UNCHANGED',
      );
    }
    final out = runPayrollAuditCore(
      managementRows: managementRows,
      agentRows: agentRows,
      userInfoRows: allRows,
      columns: req.columns,
      discountRatePct: discountRatePct,
      agentColor: req.agentColor,
      managementColor: req.managementColor,
    );

    final book = LocalWorkbookState.fromJson(
      await db.getLocalWorkbook(cycle.id),
    );
    final cycleMgmtCol = out.cycleMgmtCol;

    // Same naming and de-duplication rules as the Google target sheets.
    final titleToSheetName = <String, String>{};
    final usedNames = <String>{};
    for (final title in out.titleOrder) {
      var st = safeSheetTitle(title);
      while (usedNames.contains(st)) {
        st = '${st}_${usedNames.length}';
      }
      usedNames.add(st);
      titleToSheetName[title] = st;
    }
    final existingLower = {
      for (final k in book.targets.keys) k.toLowerCase(): k,
    };
    final auditedMemberIds = await db.auditedMemberIds(cycle.id);
    for (final title in out.titleOrder) {
      var sheetName = titleToSheetName[title]!;
      final items = out.byTitle[title] ?? const <TitleItem>[];
      if (items.isEmpty) continue;
      sheetName = existingLower[sheetName.toLowerCase()] ?? sheetName;
      final target = book.targets.putIfAbsent(sheetName, () => <TargetRow>[]);
      existingLower[sheetName.toLowerCase()] = sheetName;
      final existingIds = <String>{};
      for (var idx = 0; idx < target.length; idx++) {
        if (idx == 0 && isHeaderRowGeneric(target[idx].values, cycleMgmtCol)) {
          continue;
        }
        final id = normalizeUserId(cellAt(target[idx].values, cycleMgmtCol));
        if (id.isNotEmpty) existingIds.add(id);
      }
      final seen = <String>{};
      for (final it in items) {
        final id = normalizeUserId(cellAt(it.managementRow, cycleMgmtCol));
        if (id.isEmpty ||
            existingIds.contains(id) ||
            auditedMemberIds.contains(id)) {
          continue;
        }
        if (!seen.add(id)) continue;
        target.add(TargetRow(List<String>.from(it.managementRow), null));
      }
    }

    final writes = _salaryStatusColumns(req, out);
    final userInfoOut = [
      for (final r in allRows) <Object?>[...r],
    ];
    final salaryIdx = columnLetterToIndex(writes.salaryColLetter);
    final statusIdx = columnLetterToIndex(writes.statusColLetter);
    if (salaryIdx != null && statusIdx != null) {
      for (var r = writes.minRow; r <= writes.maxRow; r++) {
        final i = r - writes.minRow;
        final row = userInfoOut[r - 1];
        _setCell(row, salaryIdx, writes.salaryValues[i].first);
        _setCell(row, statusIdx, writes.statusValues[i].first);
      }
    }
    book.userInfoFileName = ui.fileName;
    book.userInfoSheetName = ui.sheetName;
    book.userInfoRows = userInfoOut;

    final colors = _sourceColors(out);
    book.mgmtColors.addAll(colors.mgmt);
    book.agentColors.addAll(colors.agent);
    await db.saveLocalWorkbook(cycle.id, book.toJson());

    final result = await _finish(
      cycle: cycle,
      out: out,
      managementRows: managementRows,
      agentRows: agentRows,
      cycleMgmtSheetName: cycle.managementSheetName,
      cycleAgentSheetName: cycle.agentSheetName,
      userInfoHash: userInfoHash,
      spreadsheetUrl: null,
      cycleSynced: false,
      localOnly: true,
    );
    await db.addAuditRun(cycle.id, 'local', result.toLog());
    return result;
  }

  // ======================================================================
  // Shared
  // ======================================================================

  static String _duplicateMessage(List<int> rows) =>
      'جدول معلومات المستخدمين يحتوي رقم مستخدم مكرراً في عمود المعرف. أزل التكرار (صفوف: '
      '${rows.take(20).join(', ')}${rows.length > 20 ? '…' : ''}).';

  static void _setCell(List<Object?> row, int idx, Object? value) {
    while (row.length <= idx) {
      row.add('');
    }
    row[idx] = value;
  }

  _ColumnWrites _salaryStatusColumns(PayrollRequest req, AuditCoreOutput out) {
    final salaryText = req.columns.userInfoSalaryCol.trim();
    final salaryColLetter =
        salaryText.isNotEmpty ? salaryText.toUpperCase() : 'L';
    final salaryColIdx = columnLetterToIndex(salaryColLetter) ?? 11;
    final statusText = req.userInfoStatusCol?.trim() ?? '';
    final statusColLetter =
        statusText.isNotEmpty
            ? statusText.toUpperCase()
            : columnIndexToLetter(salaryColIdx + 1);
    final minRow = out.dataStart + 1;
    final maxRow = out.dataStart + out.dataRows.length;
    final byRowSalary = <int, Object?>{};
    final byRowStatus = <int, String>{};
    for (final r in out.results) {
      if (isAgentType(r.type) || r.type == typeManagement) {
        byRowSalary[r.rowIndex] =
            r.salaryValue == null ? '' : _num(r.salaryValue!);
        byRowStatus[r.rowIndex] = r.statusLabel;
      } else if (r.type == typeNotFound) {
        byRowSalary[r.rowIndex] = 0;
        byRowStatus[r.rowIndex] = typeNotFound;
      }
    }
    final salaryValues = <List<Object?>>[];
    final statusValues = <List<Object?>>[];
    for (var r = minRow; r <= maxRow; r++) {
      salaryValues.add([byRowSalary.containsKey(r) ? byRowSalary[r] : '']);
      statusValues.add([byRowStatus[r] ?? '']);
    }
    return _ColumnWrites(
      salaryColLetter: salaryColLetter,
      statusColLetter: statusColLetter,
      minRow: minRow,
      maxRow: maxRow,
      salaryValues: salaryValues,
      statusValues: statusValues,
    );
  }

  static num _num(double v) =>
      v == v.truncateToDouble() && v.abs() < 1e15 ? v.toInt() : v;

  ({Map<int, String> mgmt, Map<int, String> agent}) _sourceColors(
    AuditCoreOutput out,
  ) {
    final mgmt = <int, String>{};
    final agent = <int, String>{};
    for (final r in out.results) {
      if (isAgentType(r.type) && r.mgmtSheetRowIndex != null) {
        mgmt[r.mgmtSheetRowIndex!] = out.agentColorVal;
      } else if (r.type == typeManagement && r.mgmtSheetRowIndex != null) {
        mgmt[r.mgmtSheetRowIndex!] = out.mgmtColorVal;
      }
      if (isAgentType(r.type)) {
        for (final idx in r.agentSheetRowIndices) {
          agent[idx] = out.agentColorVal;
        }
      }
    }
    return (mgmt: mgmt, agent: agent);
  }

  static List<Map<String, dynamic>> _colorRequests(
    int sheetId,
    Map<int, String> byRow,
    int endColumn,
  ) {
    final keys = byRow.keys.toList()..sort();
    return [
      for (final rowIdx in keys)
        colorRowRequest(sheetId, rowIdx, byRow[rowIdx]!, endColumn: endColumn),
    ];
  }

  Future<PayrollResult> _finish({
    required Cycle cycle,
    required AuditCoreOutput out,
    required Rows managementRows,
    required Rows agentRows,
    required String? cycleMgmtSheetName,
    required String? cycleAgentSheetName,
    required String userInfoHash,
    required String? spreadsheetUrl,
    required bool cycleSynced,
    required bool localOnly,
  }) async {
    final summary = out.summary;
    final appliedCount = summary.agent + summary.management;
    var message =
        localOnly ? 'تم تنفيذ التدقيق على الهاتف' : 'تم تنفيذ التدقيق';
    if (summary.total == 0) {
      message =
          'لم تُقرأ أي صفوف من جدول معلومات المستخدمين. تحقق من أن الورقة تحتوي بيانات وأن عمود رقم المستخدم وعمود اسم الورقة مملوءان.';
    } else if (appliedCount == 0) {
      message =
          'لم يُطابق أي صف (0 سحب وكالة، 0 سحب إدارة). يُقارن رقم المستخدم من عمود معلومات المستخدمين مع عمودي الإدارة والوكيل. تحقق من تطابق الأرقام أو من اختيار الأعمدة الصحيحة (انظر العينة أدناه).';
    }

    final sampleUserIds = <String>[];
    final sampleMgmtIds = <String>[];
    final sampleAgentIds = <String>[];
    PayrollDiagnostic? diagnostic;
    if (appliedCount == 0 && summary.total > 0) {
      void sample(Rows rows, int col, List<String> into) {
        final seen = <String>{};
        for (final r in rows) {
          final id = normalizeUserId(cellAt(r, col));
          if (id.isNotEmpty && seen.add(id)) {
            into.add(id);
            if (into.length >= 12) break;
          }
        }
      }

      sample(out.dataRows, out.colC, sampleUserIds);
      sample(out.mgmtDataRows, out.cycleMgmtCol, sampleMgmtIds);
      sample(out.agentDataRows, out.cycleAgentCol, sampleAgentIds);
      diagnostic = PayrollDiagnostic(
        managementUniqueCount: out.mgmtByUserId.length,
        agentUniqueCount: out.agentByUserId.length,
        userInfoUniqueCount:
            {
              for (final r in out.results)
                if (r.userId.isNotEmpty) r.userId,
            }.length,
        sampleCheck: [
          for (final uid in sampleUserIds.take(5))
            SampleCheck(
              uid,
              out.mgmtByUserId.containsKey(uid),
              out.agentByUserId.containsKey(uid),
            ),
        ],
      );
    }

    final auditedAgent = <String>{};
    final auditedMgmt = <String>{};
    final entries = <AuditEntry>[];
    for (final r in out.results) {
      if (isAgentType(r.type) && r.userId.isNotEmpty) {
        auditedAgent.add(r.userId);
      }
      if (r.type == typeManagement && r.userId.isNotEmpty) {
        auditedMgmt.add(r.userId);
      }
      if (r.userId.isNotEmpty &&
          (isAgentType(r.type) || r.type == typeManagement)) {
        entries.add(
          AuditEntry(
            r.userId,
            'مدقق',
            isAgentType(r.type)
                ? 'تدقيق وكيل من النظام'
                : 'تدقيق ادارة من النظام',
            {
              'type': r.type,
              'title': r.title,
              'salaryAfterDiscount':
                  r.salaryValue == null ? '' : _num(r.salaryValue!),
            },
          ),
        );
      }
    }
    await db.saveUserAuditStatuses(cycle.id, entries);
    await db.saveCycleCache(
      cycle.id,
      CycleCache(
        managementData: managementRows,
        agentData: agentRows,
        managementSheetName: cycleMgmtSheetName,
        agentSheetName: cycleAgentSheetName,
        auditedAgentIds: auditedAgent,
        auditedMgmtIds: auditedMgmt,
        foundInTargetSheetIds: <String>{},
      ),
    );
    await db.updateCycle(cycle.id, {
      'payroll_audit_user_info_hash': userInfoHash,
    });

    return PayrollResult(
      success: true,
      message: message,
      summary: summary,
      applied: appliedCount > 0,
      cycleSynced: cycleSynced,
      localOnly: localOnly,
      spreadsheetUrl: spreadsheetUrl,
      results: out.results,
      sampleUserIds: sampleUserIds,
      sampleMgmtIds: sampleMgmtIds,
      sampleAgentIds: sampleAgentIds,
      diagnostic: diagnostic,
    );
  }
}

Map<String, dynamic> colorRowRequest(
  int sheetId,
  int rowIdx,
  String color, {
  int endColumn = 200,
}) => {
  'repeatCell': {
    'range': {
      'sheetId': sheetId,
      'startRowIndex': rowIdx,
      'endRowIndex': rowIdx + 1,
      'startColumnIndex': 0,
      'endColumnIndex': endColumn,
    },
    'cell': {
      'userEnteredFormat': {'backgroundColor': hexToRgb(color)},
    },
    'fields': 'userEnteredFormat.backgroundColor',
  },
};

class _ColumnWrites {
  const _ColumnWrites({
    required this.salaryColLetter,
    required this.statusColLetter,
    required this.minRow,
    required this.maxRow,
    required this.salaryValues,
    required this.statusValues,
  });
  final String salaryColLetter;
  final String statusColLetter;
  final int minRow;
  final int maxRow;
  final List<List<Object?>> salaryValues;
  final List<List<Object?>> statusValues;
}

class TargetRow {
  TargetRow(this.values, this.color);
  final List<String> values;
  final String? color;
}

/// The phone-side equivalent of the Google spreadsheets the ERP audit
/// writes to: target sheets, source row colors and the user-info table
/// with salary/status filled in. Exported as one Excel workbook.
class LocalWorkbookState {
  LocalWorkbookState({
    Map<String, List<TargetRow>>? targets,
    Map<int, String>? mgmtColors,
    Map<int, String>? agentColors,
    this.userInfoFileName,
    this.userInfoSheetName,
    this.userInfoRows,
  }) : targets = targets ?? <String, List<TargetRow>>{},
       mgmtColors = mgmtColors ?? <int, String>{},
       agentColors = agentColors ?? <int, String>{};

  final Map<String, List<TargetRow>> targets;
  final Map<int, String> mgmtColors;
  final Map<int, String> agentColors;
  String? userInfoFileName;
  String? userInfoSheetName;
  List<List<Object?>>? userInfoRows;

  bool get isEmpty =>
      targets.isEmpty &&
      mgmtColors.isEmpty &&
      agentColors.isEmpty &&
      userInfoRows == null;

  Map<String, Object?> toJson() => {
    'targets': [
      for (final e in targets.entries)
        {
          'name': e.key,
          'rows': [
            for (final r in e.value) {'v': r.values, 'c': r.color},
          ],
        },
    ],
    'mgmtColors': {for (final e in mgmtColors.entries) '${e.key}': e.value},
    'agentColors': {for (final e in agentColors.entries) '${e.key}': e.value},
    'userInfoFileName': userInfoFileName,
    'userInfoSheetName': userInfoSheetName,
    'userInfoRows': userInfoRows,
  };

  static LocalWorkbookState fromJson(Map<String, Object?>? j) {
    if (j == null) return LocalWorkbookState();
    final targets = <String, List<TargetRow>>{};
    for (final t in (j['targets'] as List? ?? const [])) {
      final m = t as Map;
      targets[m['name'].toString()] = [
        for (final r in (m['rows'] as List? ?? const []))
          TargetRow([
            for (final c in ((r as Map)['v'] as List? ?? const []))
              c?.toString() ?? '',
          ], r['c'] as String?),
      ];
    }
    Map<int, String> colors(Object? v) => {
      if (v is Map)
        for (final e in v.entries)
          int.parse(e.key.toString()): e.value.toString(),
    };
    final ui = j['userInfoRows'];
    return LocalWorkbookState(
      targets: targets,
      mgmtColors: colors(j['mgmtColors']),
      agentColors: colors(j['agentColors']),
      userInfoFileName: j['userInfoFileName'] as String?,
      userInfoSheetName: j['userInfoSheetName'] as String?,
      userInfoRows:
          ui is List
              ? [
                for (final r in ui)
                  if (r is List) List<Object?>.from(r) else <Object?>[],
              ]
              : null,
    );
  }
}

String formatNumber(num v) => jsNumberToString(v);
