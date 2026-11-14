import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/local_audit_database.dart';
import '../domain/audit_engine.dart';
import '../google/google_sheets_gateway.dart';
import 'audit_planner.dart';

/// Reads the exact Google sources associated with the saved cycle and prepares
/// a preview only. This service never persists operations or writes to Google.
/// A proof is recorded when each source is downloaded; old text-only snapshots
/// cannot establish the original cell types and must be downloaded again.
class AuditPlanReviewService {
  AuditPlanReviewService(this.database, this.gateway);

  final LocalAuditDatabase database;
  final SheetsGateway gateway;

  /// Store alongside the displayed rows from the same read. The digest covers
  /// source identity, row positions, original cell types, displayed values and
  /// colors; it contains neither an access token nor the spreadsheet contents.
  static Map<String, Object?> captureProof(GoogleSheetData data) {
    final account = data.originAccountId;
    final spreadsheet = data.originSpreadsheetId;
    if (account == null ||
        account.isEmpty ||
        spreadsheet == null ||
        spreadsheet.isEmpty) {
      throw StateError(
        'تعذر التحقق من مصدر البيانات. أعد تحميل الملف من Google.',
      );
    }
    _validateRows(data);
    final payload = <String, Object?>{
      'version': 1,
      'accountId': account,
      'spreadsheetId': spreadsheet,
      'sheetId': data.ref.id,
      'sheetTitle': data.ref.title,
      'merges': data.merges,
      'protectedRanges': data.protectedRanges,
      'rows':
          data.rows
              .map(
                (row) => <String, Object?>{
                  'index': row.index,
                  'cells':
                      row.cells
                          .map(
                            (cell) => <String, Object?>{
                              'entered': cell.entered,
                              'formatted': cell.formatted,
                              'color': cell.color,
                            },
                          )
                          .toList(),
                },
              )
              .toList(),
    };
    final rowHashes =
        data.rows
            .map(
              (row) => <String, Object?>{
                'index': row.index,
                'sha256': _rowFingerprint(row),
              },
            )
            .toList();
    final visibleRowsHash =
        sha256
            .convert(utf8.encode(jsonEncode(_canonical(_displayRows(data)))))
            .toString();
    return <String, Object?>{
      'version': 2,
      'sha256':
          sha256
              .convert(utf8.encode(jsonEncode(_canonical(payload))))
              .toString(),
      'rowHashes': rowHashes,
      'displayRowsSha256': visibleRowsHash,
    };
  }

  Future<AuditPlanPreview> prepare({
    required String cycleId,
    required String accountId,
    required String agentColor,
    required String managementColor,
    Set<String>? onlyMemberIds,
    Map<String, String> manualTargets = const {},
  }) async {
    if (cycleId.trim().isEmpty || accountId.trim().isEmpty) {
      throw StateError('اختر الدورة واربط حساب Google أولًا.');
    }
    final cycle = await database.getCycle(cycleId);
    if (cycle == null || cycle.auditClosed) {
      throw StateError('الدورة مغلقة أو غير موجودة.');
    }
    final info = cycle.snapshots['userInfoSource'];
    final target = cycle.snapshots['auditTarget'];
    if (info is! Map || target is! Map) {
      throw StateError('احفظ معلومات المستخدمين ووجهة التدقيق أولًا.');
    }
    final targetId = target['id'];
    if (targetId is! String ||
        targetId.trim().isEmpty ||
        target['accountId'] != accountId) {
      throw StateError('اختر وجهة التدقيق من حساب Google المتصل.');
    }

    final management = await _readApprovedSource(
      accountId,
      cycle.managementSource,
      cycle.snapshots['management'],
      'الإدارة',
    );
    final agent = await _readApprovedSource(
      accountId,
      cycle.agentSource,
      cycle.snapshots['agent'],
      'الوكيل',
    );
    final userInfo = await _readApprovedSource(
      accountId,
      info,
      cycle.snapshots['userInfo'],
      'معلومات المستخدمين',
    );

    // Recheck after asynchronous Google reads. Changes during preparation must
    // not silently replace the local source or the approved settings.
    await _ensureCycleUnchanged(cycle);
    final mappings = cycle.columnMappings;
    String column(String key) {
      final value = mappings[key];
      if (value is! String || value.trim().isEmpty) {
        throw StateError('إعدادات أعمدة التدقيق غير مكتملة.');
      }
      return value;
    }

    bool header(String key) {
      final value = mappings[key];
      if (value is! bool) throw StateError('حدد صف العناوين لكل مصدر.');
      return value;
    }

    final status = mappings['userInfoStatus'];
    if (status != null && status is! String) {
      throw StateError('إعداد عمود حالة التدقيق غير صالح.');
    }
    final blocked = <String, String>{};
    void recordChanges(
      Map<String, Object?> metadata,
      Object? savedRows,
      GoogleSheetData live,
      String idColumn,
      bool hasHeader,
      String label,
    ) {
      for (final id in _changedMemberIds(
        metadata: metadata,
        savedRows: savedRows,
        live: live,
        idColumn: idColumn,
        hasHeader: hasHeader,
      )) {
        blocked.putIfAbsent(
          id,
          () =>
              'تغير صف $label لهذا المستخدم منذ اعتماد اللقطة؛ أعد مراجعته قبل المتابعة.',
        );
      }
    }

    recordChanges(
      cycle.managementSource,
      cycle.snapshots['management'],
      management.$2,
      column('managementId'),
      header('managementHeader'),
      'الإدارة',
    );
    recordChanges(
      cycle.agentSource,
      cycle.snapshots['agent'],
      agent.$2,
      column('agentId'),
      header('agentHeader'),
      'الوكيل',
    );
    recordChanges(
      Map<String, Object?>.from(info),
      cycle.snapshots['userInfo'],
      userInfo.$2,
      column('userInfoId'),
      header('userInfoHeader'),
      'معلومات المستخدمين',
    );
    final preview = await AuditPlanner(database).preview(
      PlannerRequest(
        cycleId: cycleId,
        accountId: accountId,
        management: PlannerSource(
          spreadsheetId: management.$1,
          snapshot: management.$2,
          idColumn: column('managementId'),
          hasHeader: header('managementHeader'),
        ),
        agent: PlannerSource(
          spreadsheetId: agent.$1,
          snapshot: agent.$2,
          idColumn: column('agentId'),
          hasHeader: header('agentHeader'),
        ),
        userInfo: PlannerSource(
          spreadsheetId: userInfo.$1,
          snapshot: userInfo.$2,
          idColumn: column('userInfoId'),
          hasHeader: header('userInfoHeader'),
        ),
        titleColumn: column('userInfoTitle'),
        targetSpreadsheetId: targetId,
        agentColor: agentColor,
        managementColor: managementColor,
        statusColumn: status as String?,
        statusColumnIsVerifiedNonFinancial:
            mappings['userInfoStatusConfirmed'] == true,
        onlyMemberIds: onlyMemberIds,
        manualTargets: manualTargets,
        blockedMemberIssues: blocked,
      ),
    );
    await _ensureCycleUnchanged(cycle);
    return preview;
  }

  Future<(String, GoogleSheetData)> _readApprovedSource(
    String accountId,
    Map<dynamic, dynamic> source,
    Object? savedRows,
    String label,
  ) async {
    final spreadsheet = source['spreadsheetId'];
    final sheetId = source['sheetId'];
    final title = source['sheetTitle'];
    final proof = source['googleReviewProof'];
    if (source['kind'] != 'google') {
      throw StateError(
        'معاينة خطة Google لا تدعم حاليًا مصدر $label من ملف محلي.',
      );
    }
    if (source['accountId'] != accountId ||
        spreadsheet is! String ||
        spreadsheet.trim().isEmpty ||
        sheetId is! int ||
        title is! String ||
        title.isEmpty) {
      throw StateError('حساب أو ملف $label مختلف عن الإعدادات المحفوظة.');
    }
    if (proof is! Map ||
        proof['version'] != 2 ||
        proof['sha256'] is! String ||
        proof['rowHashes'] is! List ||
        proof['displayRowsSha256'] is! String) {
      throw StateError(
        'لقطة $label لا تحتوي بصمات صفوف قابلة للمراجعة الفردية. أعد تحميلها ثم راجع المعاينة.',
      );
    }
    if (savedRows is! List ||
        sha256
                .convert(utf8.encode(jsonEncode(_canonical(savedRows))))
                .toString() !=
            proof['displayRowsSha256']) {
      throw StateError(
        'لقطة $label المحلية تغيرت. أعد تحميلها ثم راجع المعاينة.',
      );
    }
    final data = await gateway.readSheet(accountId, spreadsheet, sheetId);
    if (data.originAccountId != accountId ||
        data.originSpreadsheetId != spreadsheet ||
        data.ref.id != sheetId ||
        data.ref.title != title) {
      throw StateError(
        'تغيرت هوية مصدر $label بعد المعاينة. أعد تحميله وراجع التدقيق.',
      );
    }
    return (spreadsheet, data);
  }

  Future<void> _ensureCycleUnchanged(CycleRecord original) async {
    final current = await database.getCycle(original.id);
    if (current == null ||
        current.auditClosed ||
        cycleConfigurationFingerprint(current) !=
            cycleConfigurationFingerprint(original) ||
        jsonEncode(_canonical(current.snapshots)) !=
            jsonEncode(_canonical(original.snapshots))) {
      throw StateError(
        'تغيرت الدورة أثناء التحضير. أعد فتح المعاينة وحاول مجددًا.',
      );
    }
  }
}

void _validateRows(GoogleSheetData data) {
  var lastIndex = -1;
  for (final row in data.rows) {
    if (row.index <= lastIndex || row.index > 1000000) {
      throw StateError('تعذر التحقق من ترتيب الصفوف. أعد تحميل البيانات.');
    }
    lastIndex = row.index;
  }
}

List<List<String>> _displayRows(GoogleSheetData data) {
  final rows = <List<String>>[];
  for (final row in data.rows) {
    while (rows.length <= row.index) {
      rows.add(<String>[]);
    }
    rows[row.index] =
        row.cells
            .map(
              (cell) =>
                  cell.entered['stringValue']?.toString() ?? cell.formatted,
            )
            .toList();
  }
  return rows;
}

String _rowFingerprint(GoogleRow row) {
  final cells =
      row.cells
          .map(
            (cell) => <String, Object?>{
              'entered': cell.entered,
              'formatted': cell.formatted,
              'color': cell.color,
            },
          )
          .toList();
  return sha256.convert(utf8.encode(jsonEncode(_canonical(cells)))).toString();
}

Set<String> _changedMemberIds({
  required Map<String, Object?> metadata,
  required Object? savedRows,
  required GoogleSheetData live,
  required String idColumn,
  required bool hasHeader,
}) {
  if (savedRows is! List) throw StateError('لقطة محلية مفقودة.');
  final proof = metadata['googleReviewProof'];
  if (proof is! Map || proof['rowHashes'] is! List) {
    throw StateError('بصمات صفوف المصدر غير متاحة. أعد تحميله.');
  }
  final column = columnIndex(idColumn);
  final baselineHashes = <int, String>{};
  for (final item in proof['rowHashes'] as List) {
    if (item is! Map || item['index'] is! int || item['sha256'] is! String) {
      throw StateError('بصمات صفوف المصدر غير صالحة. أعد تحميله.');
    }
    baselineHashes[item['index'] as int] = item['sha256'] as String;
  }
  final currentProof =
      AuditPlanReviewService.captureProof(live)['rowHashes'] as List;
  final currentHashes = <int, String>{
    for (final item in currentProof)
      (item as Map)['index'] as int: item['sha256'] as String,
  };
  Map<String, List<String>> collectSaved() {
    final result = <String, List<String>>{};
    for (var i = hasHeader ? 1 : 0; i < savedRows.length; i++) {
      final raw = savedRows[i];
      if (raw is! List) continue;
      final row = raw.map((value) => value?.toString() ?? '').toList();
      if (column >= row.length) continue;
      final id = normalizeMemberId(row[column]);
      if (id.isEmpty) continue;
      final hash = baselineHashes[i];
      if (hash == null) {
        throw StateError('بصمة صف $id مفقودة. أعد تحميل المصدر.');
      }
      result.putIfAbsent(id, () => <String>[]).add(hash);
    }
    return result;
  }

  Map<String, List<String>> collectLive() {
    final result = <String, List<String>>{};
    for (final row in live.rows) {
      if ((hasHeader && row.index == 0) || column >= row.cells.length) continue;
      final cell = row.cells[column];
      final rawId = cell.entered['stringValue'] ?? cell.formatted;
      final id = normalizeMemberId(rawId);
      if (id.isEmpty) continue;
      final hash = currentHashes[row.index];
      if (hash == null) {
        throw StateError('بصمة صف $id غير متاحة. أعد تحميل المصدر.');
      }
      result.putIfAbsent(id, () => <String>[]).add(hash);
    }
    return result;
  }

  final before = collectSaved();
  final after = collectLive();
  final ids = <String>{...before.keys, ...after.keys};
  return ids.where((id) {
    final oldHashes = [...?before[id]]..sort();
    final newHashes = [...?after[id]]..sort();
    return jsonEncode(oldHashes) != jsonEncode(newHashes);
  }).toSet();
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
