import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lork_audit_standalone/application/audit_plan_review_service.dart';
import 'package:lork_audit_standalone/application/audit_planner.dart';
import 'package:lork_audit_standalone/data/local_audit_database.dart';
import 'package:lork_audit_standalone/google/google_sheets_gateway.dart';
import 'package:lork_audit_standalone/sync/audit_sync_engine.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GoogleCell _text(String value) =>
    GoogleCell(entered: {'stringValue': value}, formatted: value);

GoogleSheetData _sheet(
  String spreadsheetId,
  int sheetId,
  String title,
  List<List<GoogleCell>> rows,
) => GoogleSheetData(
  originAccountId: 'account',
  originSpreadsheetId: spreadsheetId,
  ref: SheetRef(id: sheetId, title: title),
  rows: [for (var i = 0; i < rows.length; i++) GoogleRow(i, rows[i])],
  merges: const [],
  protectedRanges: const [],
);

Map<String, Object?> _source(GoogleSheetData sheet) => {
  'kind': 'google',
  'accountId': 'account',
  'spreadsheetId': sheet.originSpreadsheetId,
  'sheetId': sheet.ref.id,
  'sheetTitle': sheet.ref.title,
  'googleReviewProof': AuditPlanReviewService.captureProof(sheet),
};

List<List<String>> _visible(GoogleSheetData sheet) => [
  for (final row in sheet.rows)
    [
      for (final cell in row.cells)
        cell.entered['stringValue']?.toString() ?? cell.formatted,
    ],
];

class _ReadOnlyGateway implements SheetsGateway {
  _ReadOnlyGateway(this.sources);
  final Map<String, GoogleSheetData> sources;
  int reads = 0;
  int writes = 0;

  @override
  Future<GoogleSheetData> readSheet(
    String accountId,
    String spreadsheetId,
    int sheetId,
  ) async {
    reads++;
    final data = sources[spreadsheetId];
    if (accountId != 'account' || data == null || data.ref.id != sheetId) {
      throw StateError('unexpected source read');
    }
    return data;
  }

  @override
  Future<List<SheetRef>> listSheets(
    String accountId,
    String spreadsheetId,
  ) async =>
      spreadsheetId == 'target' ? const [] : [sources[spreadsheetId]!.ref];

  @override
  Future<List<SpreadsheetRef>> listSpreadsheets(String accountId) async =>
      const [];

  @override
  Future<void> createSheet(
    String accountId,
    String spreadsheetId,
    String title,
  ) async {
    writes++;
  }

  @override
  Future<void> writeRow(
    String accountId,
    String spreadsheetId,
    int sheetId,
    int rowIndex,
    List<Map<String, dynamic>> values,
  ) async {
    writes++;
  }

  @override
  Future<void> colorRow(
    String accountId,
    String spreadsheetId,
    int sheetId,
    int rowIndex,
    int endColumn,
    Map<String, double> color,
  ) async {
    writes++;
  }

  @override
  Future<void> writeStatus(
    String accountId,
    String spreadsheetId,
    int sheetId,
    int rowIndex,
    int columnIndex,
    String value,
  ) async {
    writes++;
  }
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String databasePath;
  late LocalAuditDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'audit-resume-integration-',
    );
    databasePath = p.join(directory.path, 'audit.db');
    database = await LocalAuditDatabase.open(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'saved plan survives restart and an uncertain operation is never resent',
    () async {
      final management = _sheet('management', 1, 'management', [
        [_text('رقم'), _text('القيمة')],
        [_text('001'), _text('original')],
      ]);
      final agent = _sheet('agent', 2, 'agent', [
        [_text('رقم')],
        [_text('001')],
      ]);
      final info = _sheet('info', 3, 'info', [
        [_text('رقم'), _text('الوجهة')],
        [_text('001'), _text('Agency')],
      ]);
      final gateway = _ReadOnlyGateway({
        'management': management,
        'agent': agent,
        'info': info,
      });
      final managementSource = _source(management);
      final agentSource = _source(agent);
      final infoSource = _source(info);
      final cycle = CycleRecord(
        id: 'cycle',
        name: 'دورة اختبار',
        createdAt: DateTime.utc(2026),
        managementSource: managementSource,
        agentSource: agentSource,
        columnMappings: const {
          'managementId': 'A',
          'agentId': 'A',
          'userInfoId': 'A',
          'userInfoTitle': 'B',
          'userInfoStatus': '',
          'managementHeader': true,
          'agentHeader': true,
          'userInfoHeader': true,
        },
        snapshots: {
          'management': _visible(management),
          'agent': _visible(agent),
          'userInfo': _visible(info),
          'userInfoSource': infoSource,
          'auditTarget': {'id': 'target', 'accountId': 'account'},
        },
      );
      await database.saveCycle(cycle);

      final preview = await AuditPlanReviewService(database, gateway).prepare(
        cycleId: cycle.id,
        accountId: 'account',
        agentColor: '#112233',
        managementColor: '#445566',
      );
      await AuditPlanner(database).saveApproved(preview);
      final planned = (await database.listOperations(cycle.id)).first;
      expect(planned.type, 'createSheet');
      expect(planned.status, OperationStatus.planned);

      // Simulate process death after a write could have started, then reopen SQLite.
      await database.putOperation(
        OperationRecord(
          id: planned.id,
          cycleId: planned.cycleId,
          memberId: planned.memberId,
          type: planned.type,
          source: planned.source,
          destination: planned.destination,
          fingerprint: planned.fingerprint,
          status: OperationStatus.executing,
          attempts: 1,
          updatedAt: DateTime.utc(2026, 11, 14, 12),
          evidence: planned.evidence,
        ),
      );
      await database.close();
      database = await LocalAuditDatabase.open(
        databasePath: databasePath,
        factory: databaseFactoryFfi,
      );

      final resumed = await AuditSyncEngine(
        database,
        gateway,
      ).execute(planned.id);
      expect(resumed.status, OperationStatus.verificationRequired);
      expect(resumed.attempts, 1);
      expect(gateway.writes, 0);
      final persisted = await database.getOperation(planned.id);
      expect(persisted!.status, OperationStatus.verificationRequired);
      final events = await database.listOperationEvents(cycle.id);
      final operationEvents = events.where(
        (event) => event['operation_id'] == planned.id,
      );
      expect(operationEvents.map((event) => event['status']), [
        'planned',
        'executing',
        'verificationRequired',
      ]);
    },
  );
}
