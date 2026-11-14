import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lork_audit_standalone/application/local_audit_service.dart';
import 'package:lork_audit_standalone/data/import_service.dart';
import 'package:lork_audit_standalone/data/local_audit_database.dart';
import 'package:lork_audit_standalone/data/local_audit_export.dart';
import 'package:lork_audit_standalone/domain/audit_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'local approval records a deduplicated batch and exports source colors',
    () async {
      final db = await LocalAuditDatabase.open(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      final service = LocalAuditService(db);
      final cycle = CycleRecord(
        id: 'test-cycle',
        name: 'دورة',
        createdAt: DateTime.utc(2026),
        managementSource: const {'nonTextCells': []},
        agentSource: const {'nonTextCells': []},
        columnMappings: const {},
        snapshots: const {
          'management': [
            ['المعرّف', 'المبلغ'],
            ['001', '42'],
            ['002', '60'],
            ['005', '20'],
          ],
          'agent': [
            ['المعرّف'],
            ['001'],
            ['٠٠١'],
            ['003'],
            ['005'],
          ],
        },
      );
      await db.saveCycle(cycle);
      const info = ImportedSheet('المستخدمون', [
        ['المعرّف', 'الوجهة'],
        ['001', 'الفرع'],
        ['002', 'الفرع'],
        ['003'],
        ['004'],
        ['005', 'الفرع'],
        ['005', 'وجهة أخرى'],
      ], {});

      LocalAuditReview review(
        CycleRecord saved, {
        String? id,
        String target = '',
      }) => service.review(
        cycle: saved,
        info: info,
        infoId: 'A',
        titleColumn: 'B',
        infoHeader: true,
        agentColor: defaultAgentColor,
        managementColor: defaultManagementColor,
        memberId: id,
        manualTarget: target,
      );

      final initial = review((await db.getCycle(cycle.id))!);
      expect(
        initial.preview.members[4].conflicts.map((c) => c.code),
        contains(AuditConflictCode.duplicateUserInfo),
      );
      expect(initial.results.map((result) => result.classification), [
        AuditClassification.agentMultiple,
        AuditClassification.management,
        AuditClassification.notFound,
        AuditClassification.notFound,
      ]);
      expect(await service.apply(initial), 4);

      final applied = (await db.getCycle(cycle.id))!;
      expect(await service.apply(review(applied)), 0);
      final manual = review(applied, id: '002', target: 'وجهة فردية');
      expect(await service.apply(manual), 1);
      await expectLater(service.apply(initial), throwsStateError);

      final history = await db.listLocalAudit(cycle.id, history: true);
      expect(history, hasLength(5));
      expect(
        (await db.listLocalAudit(cycle.id, memberId: '002')).single.target,
        'وجهة فردية',
      );
      final export = LocalAuditExport.encode(
        (await db.getCycle(cycle.id))!,
        history,
      );
      final workbook = Excel.decodeBytes(export);
      expect(workbook['الفرع'].rows.first.first?.value?.toString(), '001');
      expect(workbook['الفرع'].rows, hasLength(1));
      expect(workbook['وجهة فردية'].rows, hasLength(1));
      expect(
        workbook['الوكيل'].rows[2].first?.cellStyle?.backgroundColor.colorHex,
        'FF3b82f6'.toUpperCase(),
      );

      final beforeClose = (await db.getCycle(cycle.id))!;
      await db.closeCycle(cycle.id, localOnly: true);
      await expectLater(service.apply(review(beforeClose)), throwsStateError);
    },
  );
}
