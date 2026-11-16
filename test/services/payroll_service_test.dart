import 'package:flutter_test/flutter_test.dart';
import 'package:lork_audit_standalone/data/app_database.dart';
import 'package:lork_audit_standalone/erp/payroll_audit_engine.dart';
import 'package:lork_audit_standalone/services/cycle_service.dart';
import 'package:lork_audit_standalone/services/cycle_sync_worker.dart';
import 'package:lork_audit_standalone/services/payroll_service.dart';
import 'package:lork_audit_standalone/services/search_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_sheets.dart';

final mgmt = [
  ['رقم المستخدم', 'الاسم', 'الوكالة', 'المبلغ'],
  ['1001', 'أحمد', 'الشمال', '120'],
  ['1002', 'سارة', 'الشمال', '80'],
  ['1003', 'علي', 'الجنوب', '50'],
  ['1004', 'منى', 'الجنوب', '75'],
];
final agent = [
  ['رقم المستخدم', 'الاسم', 'ملاحظة', 'الراتب'],
  ['1001', 'أحمد', '', '100'],
  ['1002', 'سارة', '', '60'],
  ['1002', 'سارة', 'راتب ثانٍ', '40'],
  ['1007', 'باسم', '', '30'],
];
final userInfo = [
  ['الاسم', 'الهاتف', 'رقم المستخدم', 'الوكيل'],
  ['أحمد', '0991', '1001', 'وكيل الشمال'],
  ['سارة', '0992', '1002', 'وكيل الشمال'],
  ['علي', '0993', '1003', 'وكيل الجنوب'],
  ['خالد', '0995', '1009', 'وكيل الشمال'],
];

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late FakeSheets fake;
  late PayrollService payroll;
  late SearchService search;

  setUp(() async {
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    fake =
        FakeSheets()
          ..add('cyc', 'الإدارة', mgmt)
          ..add('cyc', 'الوكيل', agent)
          ..add('cyc', 'وكيل الشمال', [
            mgmt[0],
            ['1001', 'أحمد', 'الشمال', '120'],
          ])
          ..add('ui', 'Sheet1', userInfo);
    payroll = PayrollService(db, () => fake);
    search = SearchService(db, () => fake);
  });

  tearDown(() => db.close());

  PayrollRequest request(int id, {bool force = false}) => PayrollRequest(
    cycleId: id,
    userInfo: const GoogleUserInfo('ui', null),
    discountRate: 10,
    agentColor: '#8b5cf6',
    managementColor: '#facc15',
    columns: const AuditColumns(),
    forceReaudit: force,
  );

  Future<int> linkedCycle() => db.insertCycle(
    name: 'مرتبطة',
    managementRows: const [],
    agentRows: const [],
    managementSpreadsheetId: 'cyc',
    managementSheetName: 'الإدارة',
    agentSpreadsheetId: 'cyc',
    agentSheetName: 'الوكيل',
  );

  test('Google mode writes what ERP payroll-execute writes', () async {
    final id = await linkedCycle();
    final r = await payroll.execute(request(id));
    expect(r.success, isTrue, reason: r.message);
    expect(r.cycleSynced, isTrue);
    expect(r.summary!.agent, 2);
    expect(r.summary!.management, 1);
    expect(r.summary!.notFound, 1);

    // 1001 already existed in «وكيل الشمال»; only 1002 is appended.
    expect(fake.books['cyc']!['وكيل الشمال']!.map((e) => e.first), [
      'رقم المستخدم',
      '1001',
      '1002',
    ]);
    expect(fake.books['cyc']!['وكيل الجنوب'], [
      ['1003', 'علي', 'الجنوب', '50'],
    ]);
    final ui = fake.books['ui']!['Sheet1']!;
    expect([for (final row in ui.skip(1)) row[11]], ['90', '90', '0', '0']);
    expect(
      [for (final row in ui.skip(1)) row[12]],
      ['سحب وكيل', 'سحب وكيل راتبين', 'سحب ادارة', 'غير موجود'],
    );
    final mgmtColors = fake.colors['cyc|${fake.ids['cyc']!['الإدارة']}']!;
    expect(mgmtColors, {1: '#8b5cf6', 2: '#8b5cf6', 3: '#facc15'});
    final agentColors = fake.colors['cyc|${fake.ids['cyc']!['الوكيل']}']!;
    expect(agentColors, {1: '#8b5cf6', 2: '#8b5cf6', 3: '#8b5cf6'});
  });

  test('re-running never copies an audited row twice', () async {
    final id = await linkedCycle();
    await payroll.execute(request(id));
    await payroll.execute(request(id, force: true));
    await payroll.execute(request(id, force: true));
    expect(fake.books['cyc']!['وكيل الشمال']!.length, 3);
    expect(fake.books['cyc']!['وكيل الجنوب']!.length, 1);
  });

  test('a cycle from files gets its own Google spreadsheet', () async {
    final id = await db.insertCycle(
      name: 'ملفات',
      managementRows: mgmt,
      agentRows: agent,
    );
    final r = await payroll.execute(request(id));
    expect(r.success, isTrue, reason: r.message);
    final cycle = await db.getCycle(id);
    expect(cycle!.linkedToGoogle, isTrue);
    expect(cycle.managementSheetName, 'الإدارة');
    expect(cycle.agentSheetName, 'الوكيل');
    final book = fake.books[cycle.managementSpreadsheetId]!;
    expect(book.keys, containsAll(['الإدارة', 'الوكيل', 'وكيل الشمال']));
  });

  test('search and selective audit', () async {
    final id = await linkedCycle();
    await payroll.execute(request(id));
    final s = await search.searchUser(id, '١٠٠٢', 10);
    expect(s.hits.single.logicalStatus, statusAgentTwo);
    expect(s.hits.single.salaryAfter, 90);
    expect(s.hits.single.auditStatus, 'مدقق');

    final ia = await search.executeIndividual(
      cycleId: id,
      memberIdRaw: '1004',
      targetSheetTitle: 'يدوي',
      createIfMissing: true,
      agentColor: '#8b5cf6',
      managementColor: '#facc15',
    );
    expect(ia.success, isTrue, reason: ia.message);
    expect(fake.books['cyc']!['يدوي'], [
      ['1004', 'منى', 'الجنوب', '75'],
    ]);
    final after = await search.searchUser(id, '1004', 0);
    expect(after.hits.single.auditStatus, 'مدقق');
    expect(after.hits.single.auditSource, 'تدقيق من أداة البحث');
  });

  test('local mode keeps the same effects in a workbook', () async {
    final id = await db.insertCycle(
      name: 'محلية',
      managementRows: mgmt,
      agentRows: agent,
    );
    final r = await payroll.execute(
      PayrollRequest(
        cycleId: id,
        userInfo: LocalUserInfo('ui.csv', 'CSV', userInfo),
        discountRate: null,
        agentColor: '#8b5cf6',
        managementColor: '#facc15',
        columns: const AuditColumns(),
      ),
    );
    expect(r.success, isTrue, reason: r.message);
    expect(r.localOnly, isTrue);
    expect(fake.log, isEmpty);
    final state = LocalWorkbookState.fromJson(await db.getLocalWorkbook(id));
    expect(state.targets.keys, ['وكيل الشمال', 'وكيل الجنوب']);
    expect(state.mgmtColors, {1: '#8b5cf6', 2: '#8b5cf6', 3: '#facc15'});
    expect(state.userInfoRows![1][11], 100);
    expect(state.userInfoRows![1][12], 'سحب وكيل');
  });

  test('search reads only the cycle cache, like ERP', () async {
    final id = await linkedCycle();
    final before = await search.searchUser(id, '1001', 0);
    expect(before.success, isFalse);
    expect(before.message, contains('لم يتم مزامنة الدورة بعد'));
    final all = await search.searchAcrossCycles('1001', 0);
    expect(all.success, isFalse);
  });

  test(
    'cycle sync stores the user-info snapshot (ERP /cycles/:id/sync)',
    () async {
      final id = await linkedCycle();
      final cycles = CycleService(db, () => fake);
      final r = await cycles.syncCycle(id, userInfoSpreadsheetId: 'ui');
      expect(r.success, isTrue, reason: r.message);
      expect(
        r.message,
        'تمت مزامنة جداول الدورة ومعلومات المستخدمين من Google',
      );
      final cycle = await db.getCycle(id);
      expect(cycle!.managementRows.length, mgmt.length);

      final local = await db.insertCycle(
        name: 'ملفات',
        managementRows: mgmt,
        agentRows: agent,
      );
      final unlinked = await cycles.syncCycle(local);
      expect(unlinked.success, isFalse);
      expect(unlinked.message, contains('غير مرتبطة بجداول Google'));
    },
  );

  test('background sync marks coloured rows as manually audited', () async {
    final id = await linkedCycle();
    fake.colors['cyc|${fake.ids['cyc']!['الإدارة']}'] = {2: '#facc15'};
    fake.colors['cyc|${fake.ids['cyc']!['الوكيل']}'] = {
      2: '#8b5cf6',
      3: '#8b5cf6',
    };
    final worker = CycleSyncWorker(db, () => fake);
    expect(await worker.runOnce(), 0, reason: 'off by default, like ERP');
    await db.setValue(CycleSyncWorker.enabledKey, '1');
    expect(await worker.runOnce(), 1);
    final cache = await db.getCycleCache(id);
    expect(cache!.auditedMgmtIds, {'1002'});
    expect(cache.auditedAgentIds, {'1002'});
    expect(cache.staleAfter!.isAfter(DateTime.now()), isTrue);
    expect(await worker.runOnce(), 0, reason: 'cache still fresh');

    final s = await search.searchUser(id, '1002', 0);
    expect(s.hits.single.auditStatus, 'مدقق');
    expect(s.hits.single.auditSource, 'مدقق يدوي');
    final other = await search.searchUser(id, '1001', 0);
    expect(other.hits.single.auditStatus, 'غير مدقق');
  });
}
