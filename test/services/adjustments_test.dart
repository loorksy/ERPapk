import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lork_audit_standalone/data/app_database.dart';
import 'package:lork_audit_standalone/services/adjustments_service.dart';
import 'package:lork_audit_standalone/services/audit_job_runner.dart';
import 'package:lork_audit_standalone/services/cycle_service.dart';
import 'package:lork_audit_standalone/services/payroll_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_sheets.dart';

/// A user-info row: id in C, salary in L, status in O (ERP defaults).
List<String> uiRow(String id, String salary) => [
  'n$id',
  '',
  id,
  'وكالة',
  for (var i = 4; i < 11; i++) '',
  salary,
  '',
  '',
  '',
];

final sheet = [
  [
    'A',
    'B',
    'ID',
    'D',
    for (var i = 4; i < 11; i++) 'c$i',
    'Salary',
    'M',
    'N',
    'Status',
  ],
  uiRow('1001', '10'),
  uiRow('1002', '100'),
  uiRow('1003', '40'),
  uiRow('1004', '75'),
];

String status(BulkComputation c, int row) =>
    c.writes.firstWhere((w) => w.row == row).status;
String salary(BulkComputation c, int row) =>
    c.writes.firstWhere((w) => w.row == row).salary;

void main() {
  sqfliteFfiInit();

  test('ERP order: a deduction then an addition leaves a wrong debt', () {
    final erp = AdjustmentsService.computeBulk(
      '1001\tخصم\t50\n1001\tاضافة\t30',
      sheet,
      settle: false,
    );
    // ERP: 10 − 50 → 0 with 40 still owed, then + 30 → 30.
    expect(erp.results.map((r) => r.status), ['باقي عليه', 'تمت الإضافة']);
    expect(salary(erp, 2), '30.00');
    expect(AdjustmentsService.summarize(erp.results).totalDebt, 40);
  });

  test('settlement: additions and deductions of one id are netted first', () {
    final c = AdjustmentsService.computeBulk(
      '1001\tخصم\t50\n1002\tخصم\t20\n1001\tاضافة\t30',
      sheet,
    );
    // 1001: +30 − 50 = −20 on a salary of 10 → 0, 10 still owed.
    expect(c.results.length, 2);
    expect(c.results[0].id, '1001');
    expect(c.results[0].status, 'باقي عليه');
    expect(c.results[0].debt, 10);
    expect(c.results[0].settlement, 'إضافة 30، خصم 50');
    expect(c.results[0].displayStatus, 'باقي عليه (تسوية)');
    expect(salary(c, 2), '0.00');
    expect(status(c, 2), 'تم خصم 20 (تسوية: إضافة 30، خصم 50)');
    // 1002 has only a deduction: ERP's line as is.
    expect(c.results[1].status, 'تم الخصم بالكامل');
    expect(salary(c, 3), '80.00');
    expect(status(c, 3), 'تم خصم 20');
  });

  test('settlement with a net addition, a zero net and «خصم كامل»', () {
    final c = AdjustmentsService.computeBulk(
      [
        '1002\tاضافة\t50',
        '1002\tخصم\t20',
        '1003\tخصم\t15',
        '1003\tإضافة\t15',
        '1004\tخصم كامل',
        '1004\tاضافة\t5',
      ].join('\n'),
      sheet,
    );
    expect(salary(c, 3), '130.00');
    expect(status(c, 3), 'تم اضافة 30 (تسوية: إضافة 50، خصم 20)');
    expect(salary(c, 4), '40.00');
    expect(status(c, 4), 'تمت التسوية (إضافة 15، خصم 15)');
    // «خصم كامل» is not netted: ERP order (all taken, then + 5).
    expect(c.results.where((r) => r.id == '1004').map((r) => r.status), [
      'تم خصم الدين',
      'تمت الإضافة',
    ]);
    expect(salary(c, 5), '5.00');
  });

  test('unknown ids are reported per line, like ERP', () {
    final c = AdjustmentsService.computeBulk(
      '9999\tخصم\t5\n9999\tاضافة\t7',
      sheet,
    );
    expect(c.results.map((r) => r.status), ['غير موجود', 'غير موجود']);
    expect(AdjustmentsService.summarize(c.results).totalNotFound, 12);
    expect(c.writes, isEmpty);
  });

  test('copy text like ERP (comma decimals and totals)', () {
    final c = AdjustmentsService.computeBulk('1003\tخصم\t60.5', sheet);
    final text = AdjustmentsService.copyText(
      c.results,
      AdjustmentsService.summarize(c.results),
    );
    expect(text.split('\n')[1], '1003\tباقي عليه\t\$20,5');
    expect(text, contains('مجموع المتبقي (لنا عليهم)\t\t\$20,5'));
    expect(text, contains('مجموع تم خصم\t\t\$40'));
  });

  test(
    'upgrading a 2.4 database keeps its jobs and allows cycle-less ones',
    () async {
      final dir = await Directory.systemTemp.createTemp('v4');
      final path = '${dir.path}/erp_audit.db';
      final f = databaseFactoryFfiNoIsolate;
      final old = await f.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE financial_cycles (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)',
            );
            // audit_jobs exactly as in schema 4.
            await db.execute('''CREATE TABLE audit_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cycle_id INTEGER NOT NULL REFERENCES financial_cycles(id) ON DELETE CASCADE,
      status TEXT NOT NULL,
      request_json TEXT NOT NULL,
      plan_json TEXT,
      step_next INTEGER NOT NULL DEFAULT 0,
      step_total INTEGER NOT NULL DEFAULT 0,
      progress TEXT,
      error TEXT,
      result_json TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      seen INTEGER NOT NULL DEFAULT 0,
      lease_owner TEXT,
      lease_until TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
            await db.insert('financial_cycles', {'id': 1, 'name': 'c'});
            await db.insert('audit_jobs', {
              'cycle_id': 1,
              'status': 'done',
              'request_json': '{}',
              'step_next': 7,
              'step_total': 7,
              'progress': 'تم',
              'created_at': '2026-11-16T10:00:00',
              'updated_at': '2026-11-16T10:00:00',
            });
          },
        ),
      );
      await old.close();
      final db = await AppDatabase.open(path: path, factory: f);
      final kept = (await db.latestAuditJob(1))!;
      expect(kept.stepNext, 7);
      expect(kept.progress, 'تم');
      final id = await db.createAuditJob(null, {'kind': 'adjustments'});
      expect((await db.getAuditJob(id))!.cycleId, isNull);
      await db.close();
      await dir.delete(recursive: true);
    },
  );

  group('job on Google', () {
    late AppDatabase db;
    late FakeSheets fake;
    late AuditJobRunner runner;

    setUp(() async {
      db = await AppDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      fake = FakeSheets()..add('ui', 'Data', sheet);
      final payroll = PayrollService(db, () => fake);
      runner = AuditJobRunner(
        db,
        payroll,
        CycleService(db, () => fake),
        retryDelays: const [],
      );
    });

    tearDown(() => db.close());

    Future<AuditJob> run(String bulk) async {
      final id = await db.createAuditJob(
        null,
        AdjustRequest(
          spreadsheetId: 'ui',
          sheetName: 'Data',
          bulkData: bulk,
        ).toJson(),
      );
      await runner.runPending();
      return (await db.getAuditJob(id))!;
    }

    test(
      'writes salary and status in one batch and keeps the result',
      () async {
        final job = await run('1001\tخصم\t50\n1001\tاضافة\t30\n1004\tاضافة\t5');
        expect(job.status, AuditJob.done, reason: job.error);
        expect(job.cycleId, isNull);
        final rows = fake.books['ui']!['Data']!;
        expect(rows[1][11], '0.00');
        expect(rows[1][14], 'تم خصم 20 (تسوية: إضافة 30، خصم 50)');
        expect(rows[4][11], '80.00');
        expect(rows[4][14], 'تم اضافة 5');
        expect(fake.log.where((l) => l.startsWith('BATCH VALUES')).length, 1);
        final out = AdjustOutcome.fromJson(
          (await db.getAuditJobResult(job.id))!,
        );
        expect(out.summary!.totalDebt, 10);
        expect(out.summary!.debtUsers, ['1001']);
        expect(await db.latestCyclelessJob(), isNotNull);
      },
    );

    test('a lost connection resumes without applying twice', () async {
      var down = true;
      fake.failWhen = (op, _) {
        if (down && op == 'valuesBatchUpdate') {
          down = false;
          return true;
        }
        return false;
      };
      final first = await run('1002\tخصم\t30');
      expect(first.status, AuditJob.waiting);
      expect(fake.books['ui']!['Data']![2][11], '100');
      await runner.runPending();
      final job = (await db.getAuditJob(first.id))!;
      expect(job.status, AuditJob.done, reason: job.error);
      expect(fake.books['ui']!['Data']![2][11], '70.00');
      // Running the same job again writes the same values (no double −30).
      await AdjustmentsService(db, () => fake).runStep(
        AdjustPlan.fromJson((await db.getAuditJobPlan(job.id))!),
        1,
        (_) {},
      );
      expect(fake.books['ui']!['Data']![2][11], '70.00');
    });

    test('stops if a salary changed while waiting', () async {
      var down = true;
      fake.failWhen = (op, _) {
        if (down && op == 'valuesBatchUpdate') {
          down = false;
          return true;
        }
        return false;
      };
      final first = await run('1002\tخصم\t30');
      expect(first.status, AuditJob.waiting);
      // Meanwhile the salary was edited by hand; the job restarts at the
      // check step after a restart of the app.
      fake.books['ui']!['Data']![2][11] = '500';
      await db.updateAuditJob(first.id, {'step_next': 0});
      await runner.runPending();
      final job = (await db.getAuditJob(first.id))!;
      expect(job.status, AuditJob.failed);
      expect(job.error, contains('الصف 3'));
      expect(fake.books['ui']!['Data']![2][11], '500');
    });

    test('adjustments do not wait for or block cycle audits', () async {
      final job = await run('1001\tاضافة\t1');
      expect(job.status, AuditJob.done);
      expect(await db.latestAuditJob(1), isNull);
    });
  });
}
