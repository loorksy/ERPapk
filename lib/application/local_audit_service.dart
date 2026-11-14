import '../data/import_service.dart';
import '../data/local_audit_database.dart';
import '../domain/audit_engine.dart';
import '../domain/local_audit_result.dart';

const defaultAgentColor = '#3b82f6';
const defaultManagementColor = '#10b981';

List<List<String>> cycleRows(Object? value) =>
    value is List
        ? value.whereType<List>().map((row) => List<String>.from(row)).toList()
        : [];

class LocalAuditReview {
  const LocalAuditReview(
    this.original,
    this.configured,
    this.preview,
    this.results,
  );
  final CycleRecord original;
  final CycleRecord configured;
  final AuditPreview preview;
  final List<LocalAuditResult> results;
}

class LocalAuditService {
  const LocalAuditService(this.db);
  final LocalAuditDatabase db;

  LocalAuditReview review({
    required CycleRecord cycle,
    required ImportedSheet? info,
    required String infoId,
    required String titleColumn,
    required bool infoHeader,
    required String agentColor,
    required String managementColor,
    String? memberId,
    String manualTarget = '',
  }) {
    final id = normalizeMemberId(memberId);
    final useManual = id.isNotEmpty && manualTarget.trim().isNotEmpty;
    if (info == null && !useManual) {
      throw const FormatException(
        'استورد معلومات المستخدمين أو أدخل وجهة للتدقيق الفردي.',
      );
    }
    for (final color in [agentColor, managementColor]) {
      if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
        throw const FormatException('أدخل اللون بصيغة مثل #3b82f6.');
      }
    }
    final cycleInfo = info;
    if (info != null && columnIndex(infoId) == columnIndex(titleColumn)) {
      throw const FormatException('اختر عمودًا منفصلًا لاسم الوجهة.');
    }
    cycleInfo?.validateIdentifierColumn(
      columnIndex(infoId),
      firstDataRow: infoHeader ? 1 : 0,
    );
    final infoRows = cycleInfo?.rows ?? [];
    final idIndex = cycleInfo == null ? 0 : columnIndex(infoId);
    final memberInInfo =
        id.isNotEmpty &&
        infoRows
            .skip(infoHeader ? 1 : 0)
            .any(
              (row) =>
                  row.length > idIndex && normalizeMemberId(row[idIndex]) == id,
            );
    final synthetic = useManual && !memberInInfo;
    final input = AuditInput(
      management: _source(cycle, 'management', cycle.managementSource),
      agent: _source(cycle, 'agent', cycle.agentSource),
      userInfo: AuditTable(
        rows:
            synthetic
                ? [
                  [id, manualTarget.trim()],
                ]
                : infoRows,
        idColumn: synthetic ? 'A' : infoId,
        hasHeader: !synthetic && infoHeader,
        identifiersAreTextVerified: true,
      ),
      titleColumn: synthetic ? 'B' : titleColumn,
      targetSpreadsheetId: '',
      localDestination: true,
      agentColor: agentColor.toLowerCase(),
      managementColor: managementColor.toLowerCase(),
      onlyMemberIds: id.isEmpty ? null : {id},
      manualTargets: useManual ? {id: manualTarget.trim()} : const {},
    );
    final preview = const AuditEngine().preview(input);
    final now = DateTime.now();
    final results = <LocalAuditResult>[];
    for (final member in preview.members) {
      if (member.conflicts.isNotEmpty) continue;
      final absent = member.classification == AuditClassification.notFound;
      results.add(
        LocalAuditResult(
          memberId: member.memberId,
          classification: member.classification,
          fingerprint: member.fingerprint,
          auditedAt: now,
          individual: id.isNotEmpty,
          target: absent ? null : member.targetTitle,
          managementRow: member.managementRow,
          agentRows: absent ? const [] : member.agentRows,
          color:
              absent
                  ? null
                  : member.classification == AuditClassification.management
                  ? input.managementColor
                  : input.agentColor,
        ),
      );
    }
    final configured = CycleRecord(
      id: cycle.id,
      name: cycle.name,
      createdAt: cycle.createdAt,
      auditClosed: cycle.auditClosed,
      managementSource: cycle.managementSource,
      agentSource: cycle.agentSource,
      columnMappings: {
        ...cycle.columnMappings,
        'localAgentColor': input.agentColor,
        'localManagementColor': input.managementColor,
        if (info != null) ...{
          'userInfoId': infoId.trim().toUpperCase(),
          'userInfoTitle': titleColumn.trim().toUpperCase(),
          'userInfoHeader': infoHeader,
        },
      },
      snapshots: {
        ...cycle.snapshots,
        if (info != null) ...{
          'userInfo': info.rows,
          'userInfoSource': {
            'kind': 'file',
            'label': info.name,
            'nonTextCells':
                info.nonTextCells.map((cell) => [cell.$1, cell.$2]).toList(),
          },
        },
      },
    );
    return LocalAuditReview(cycle, configured, preview, results);
  }

  Future<int> apply(LocalAuditReview review) {
    if (review.preview.conflicts.isNotEmpty || review.results.isEmpty) {
      throw StateError('لا توجد نتائج صالحة للاعتماد.');
    }
    return db.commitLocalAudit(
      expectedCycle: review.original,
      configuredCycle: review.configured,
      results: review.results,
    );
  }

  static AuditTable _source(
    CycleRecord cycle,
    String key,
    Map<String, Object?> metadata,
  ) {
    final column = cycle.columnMappings['${key}Id'] as String? ?? 'A';
    final header = cycle.columnMappings['${key}Header'] as bool? ?? true;
    final stored = cycle.snapshots[key];
    if (stored is! List) {
      throw FormatException(
        key == 'management'
            ? 'أعد استيراد بيانات الإدارة للدورة.'
            : 'أعد استيراد بيانات الوكيل أو اختر «بدون بيانات وكيل».',
      );
    }
    final rows = cycleRows(stored);
    final sheet = restoreAuditSheet(metadata, rows);
    sheet?.validateIdentifierColumn(
      columnIndex(column),
      firstDataRow: header ? 1 : 0,
    );
    final verified =
        sheet != null ||
        (cycle.columnMappings['${key}VerifiedTextColumn'] == column &&
            cycle.columnMappings['${key}VerifiedTextHeader'] == header);
    return AuditTable(
      rows: rows,
      idColumn: column,
      hasHeader: header,
      identifiersAreTextVerified: verified,
    );
  }
}

ImportedSheet? restoreAuditSheet(Map<String, Object?> metadata, Object? data) {
  final positions = metadata['nonTextCells'];
  if (data is! List || positions is! List) return null;
  final unsafe = <(int, int)>{};
  for (final cell in positions) {
    if (cell is! List ||
        cell.length != 2 ||
        cell[0] is! int ||
        cell[1] is! int) {
      return null;
    }
    unsafe.add((cell[0] as int, cell[1] as int));
  }
  return ImportedSheet(
    metadata['label'] as String? ?? 'مصدر محفوظ',
    cycleRows(data),
    unsafe,
  );
}
