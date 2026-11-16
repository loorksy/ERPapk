import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef Rows = List<List<String>>;

Rows decodeRows(String? json) {
  if (json == null || json.isEmpty) return <List<String>>[];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return <List<String>>[];
    return [
      for (final r in decoded)
        if (r is List)
          [for (final c in r) c == null ? '' : c.toString()]
        else
          <String>[],
    ];
  } catch (_) {
    return <List<String>>[];
  }
}

String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

/// Mirrors ERP's `financial_cycles` row (audit-related columns only).
class Cycle {
  Cycle({
    required this.id,
    required this.name,
    required this.managementRows,
    required this.agentRows,
    this.managementSpreadsheetId,
    this.managementSheetName,
    this.agentSpreadsheetId,
    this.agentSheetName,
    this.transferDiscountPct = 0,
    this.userInfoHash,
    this.auditClosedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final Rows managementRows;
  final Rows agentRows;
  final String? managementSpreadsheetId;
  final String? managementSheetName;
  final String? agentSpreadsheetId;
  final String? agentSheetName;
  final double transferDiscountPct;
  final String? userInfoHash;
  final DateTime? auditClosedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get linkedToGoogle =>
      managementSpreadsheetId != null && agentSpreadsheetId != null;

  static Cycle fromRow(Map<String, Object?> r) => Cycle(
    id: r['id'] as int,
    name: (r['name'] ?? '').toString(),
    managementRows: decodeRows(r['management_data'] as String?),
    agentRows: decodeRows(r['agent_data'] as String?),
    managementSpreadsheetId: _str(r['management_spreadsheet_id']),
    managementSheetName: _str(r['management_sheet_name']),
    agentSpreadsheetId: _str(r['agent_spreadsheet_id']),
    agentSheetName: _str(r['agent_sheet_name']),
    transferDiscountPct: (r['transfer_discount_pct'] as num?)?.toDouble() ?? 0,
    userInfoHash: _str(r['payroll_audit_user_info_hash']),
    auditClosedAt: _date(r['payroll_audit_closed_at']),
    createdAt: _date(r['created_at']) ?? DateTime.now(),
    updatedAt: _date(r['updated_at']) ?? DateTime.now(),
  );

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}

class CycleColumns {
  const CycleColumns({
    this.mgmtUserIdCol = 'A',
    this.agentUserIdCol = 'A',
    this.agentSalaryCol = 'D',
  });
  final String mgmtUserIdCol;
  final String agentUserIdCol;
  final String agentSalaryCol;
}

/// ERP `payroll_cycle_cache`.
class CycleCache {
  CycleCache({
    required this.managementData,
    required this.agentData,
    this.managementSheetName,
    this.agentSheetName,
    required this.auditedAgentIds,
    required this.auditedMgmtIds,
    required this.foundInTargetSheetIds,
    this.staleAfter,
  });
  final Rows managementData;
  final Rows agentData;
  final String? managementSheetName;
  final String? agentSheetName;
  final Set<String> auditedAgentIds;
  final Set<String> auditedMgmtIds;
  final Set<String> foundInTargetSheetIds;

  /// ERP `stale_after`: the background sync skips the cycle until then.
  /// Null (as saved by an audit) means "refresh on the next sync".
  final DateTime? staleAfter;
}

class UserAuditStatus {
  const UserAuditStatus(this.status, this.source, this.details);
  final String status;
  final String? source;
  final Map<String, Object?>? details;
}

class AuditEntry {
  const AuditEntry(this.memberUserId, this.status, this.source, this.details);
  final String memberUserId;
  final String status;
  final String? source;
  final Map<String, Object?>? details;
}

class PayrollSettings {
  const PayrollSettings({
    this.discountRate = 0,
    this.agentColor = '#8b5cf6',
    this.managementColor = '#facc15',
  });
  final double discountRate;
  final String agentColor;
  final String managementColor;
}

/// A Google audit run in the background (see `AuditJobRunner`).
class AuditJob {
  const AuditJob({
    required this.id,
    required this.cycleId,
    required this.status,
    required this.request,
    required this.plan,
    required this.stepNext,
    required this.stepTotal,
    required this.progress,
    required this.error,
    required this.result,
    required this.attempts,
    required this.seen,
    required this.createdAt,
    required this.updatedAt,
  });

  static const queued = 'queued';
  static const running = 'running';

  /// Interrupted (no internet, Google unreachable): resumes automatically.
  static const waiting = 'waiting';
  static const done = 'done';
  static const failed = 'failed';

  final int id;
  final int cycleId;
  final String status;
  final Map<String, Object?> request;
  final Map<String, Object?>? plan;

  /// Index of the first plan step not yet done.
  final int stepNext;
  final int stepTotal;
  final String? progress;
  final String? error;
  final Map<String, Object?>? result;
  final int attempts;

  /// The result was already announced in the app.
  final bool seen;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get active => status == queued || status == running || status == waiting;

  static Map<String, Object?>? _json(Object? v) {
    if (v == null) return null;
    try {
      final d = jsonDecode(v as String);
      return d is Map ? Map<String, Object?>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  static AuditJob fromRow(Map<String, Object?> r) => AuditJob(
    id: r['id'] as int,
    cycleId: r['cycle_id'] as int,
    status: r['status'] as String,
    request: _json(r['request_json']) ?? const {},
    plan: _json(r['plan_json']),
    stepNext: (r['step_next'] as num?)?.toInt() ?? 0,
    stepTotal: (r['step_total'] as num?)?.toInt() ?? 0,
    progress: r['progress'] as String?,
    error: r['error'] as String?,
    result: _json(r['result_json']),
    attempts: (r['attempts'] as num?)?.toInt() ?? 0,
    seen: (r['seen'] as num?) == 1,
    createdAt: DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
    updatedAt: DateTime.tryParse(r['updated_at'] as String) ?? DateTime.now(),
  );
}

class AuditRun {
  const AuditRun({
    required this.id,
    required this.cycleId,
    required this.createdAt,
    required this.mode,
    required this.payload,
  });
  final int id;
  final int cycleId;
  final DateTime createdAt;
  final String mode;
  final Map<String, Object?> payload;
}

/// All audit data lives in SQLite on the phone; no server is involved.
class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;
  static const schemaVersion = 3;

  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final location = path ?? p.join(await f.getDatabasesPath(), 'erp_audit.db');
    final db = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _create(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE payroll_cycle_cache ADD COLUMN stale_after TEXT',
            );
          }
          if (oldVersion < 3) await _createJobs(db);
        },
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _create(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE financial_cycles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      management_data TEXT,
      agent_data TEXT,
      management_spreadsheet_id TEXT,
      management_sheet_name TEXT,
      agent_spreadsheet_id TEXT,
      agent_sheet_name TEXT,
      transfer_discount_pct REAL NOT NULL DEFAULT 0,
      user_info_data TEXT,
      user_info_spreadsheet_id TEXT,
      user_info_sheet_name TEXT,
      payroll_audit_user_info_hash TEXT,
      payroll_audit_closed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE payroll_settings (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      discount_rate REAL NOT NULL DEFAULT 0,
      agent_color TEXT NOT NULL DEFAULT '#8b5cf6',
      management_color TEXT NOT NULL DEFAULT '#facc15',
      updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE payroll_cycle_columns (
      cycle_id INTEGER PRIMARY KEY REFERENCES financial_cycles(id) ON DELETE CASCADE,
      mgmt_user_id_col TEXT NOT NULL DEFAULT 'A',
      agent_user_id_col TEXT NOT NULL DEFAULT 'A',
      agent_salary_col TEXT NOT NULL DEFAULT 'D',
      updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE payroll_cycle_cache (
      cycle_id INTEGER PRIMARY KEY REFERENCES financial_cycles(id) ON DELETE CASCADE,
      management_data TEXT,
      agent_data TEXT,
      management_sheet_name TEXT,
      agent_sheet_name TEXT,
      audited_agent_ids TEXT,
      audited_mgmt_ids TEXT,
      found_in_target_sheet_ids TEXT,
      synced_at TEXT NOT NULL,
      stale_after TEXT)''');
    await db.execute('''CREATE TABLE payroll_user_audit_cache (
      cycle_id INTEGER NOT NULL REFERENCES financial_cycles(id) ON DELETE CASCADE,
      member_user_id TEXT NOT NULL,
      audit_status TEXT NOT NULL,
      audit_source TEXT,
      details_json TEXT,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (cycle_id, member_user_id))''');
    await db.execute('''CREATE TABLE local_workbooks (
      cycle_id INTEGER PRIMARY KEY REFERENCES financial_cycles(id) ON DELETE CASCADE,
      state_json TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE audit_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cycle_id INTEGER NOT NULL REFERENCES financial_cycles(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      mode TEXT NOT NULL,
      payload_json TEXT NOT NULL)''');
    await _createJobs(db);
    await db.execute('''CREATE TABLE kv (
      key TEXT PRIMARY KEY,
      value TEXT)''');
  }

  static Future<void> _createJobs(DatabaseExecutor db) =>
      db.execute('''CREATE TABLE audit_jobs (
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

  static String _now() => DateTime.now().toIso8601String();

  // ---------------------------------------------------------- audit jobs

  Future<int> createAuditJob(int cycleId, Map<String, Object?> request) {
    final now = _now();
    return _db.insert('audit_jobs', {
      'cycle_id': cycleId,
      'status': AuditJob.queued,
      'request_json': jsonEncode(request),
      'progress': 'في الانتظار...',
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Job columns without the (large) plan, for the progress display.
  static const _jobSummaryColumns = [
    'id',
    'cycle_id',
    'status',
    'request_json',
    'step_next',
    'step_total',
    'progress',
    'error',
    'result_json',
    'attempts',
    'seen',
    'created_at',
    'updated_at',
  ];

  Future<AuditJob?> getAuditJob(int id) async {
    final rows = await _db.query(
      'audit_jobs',
      columns: _jobSummaryColumns,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : AuditJob.fromRow(rows.first);
  }

  /// Jobs that still have work to do, oldest first.
  Future<List<AuditJob>> pendingAuditJobs() async {
    final rows = await _db.query(
      'audit_jobs',
      where: 'status IN (?, ?, ?)',
      whereArgs: [AuditJob.queued, AuditJob.running, AuditJob.waiting],
      orderBy: 'id',
    );
    return rows.map(AuditJob.fromRow).toList();
  }

  Future<AuditJob?> latestAuditJob(int cycleId) async {
    final rows = await _db.query(
      'audit_jobs',
      columns: _jobSummaryColumns,
      where: 'cycle_id = ?',
      whereArgs: [cycleId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : AuditJob.fromRow(rows.first);
  }

  /// Takes the job for [owner] (the app or the background worker) unless
  /// another runner holds a valid lease. One atomic UPDATE, so two runners
  /// can never both win.
  Future<bool> claimAuditJob(int id, String owner, Duration lease) async {
    final now = DateTime.now();
    final n = await _db.rawUpdate(
      'UPDATE audit_jobs SET lease_owner = ?, lease_until = ?, updated_at = ? '
      'WHERE id = ? AND (lease_until IS NULL OR lease_until < ? OR lease_owner = ?)',
      [
        owner,
        now.add(lease).toIso8601String(),
        now.toIso8601String(),
        id,
        now.toIso8601String(),
        owner,
      ],
    );
    return n == 1;
  }

  Future<void> releaseAuditJob(int id) => _db.update(
    'audit_jobs',
    {'lease_owner': null, 'lease_until': null},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> updateAuditJob(int id, Map<String, Object?> fields) =>
      _db.update(
        'audit_jobs',
        {...fields, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [id],
      );

  // ---------------------------------------------------------------- cycles

  Future<List<Cycle>> listCycles() async {
    final rows = await _db.query(
      'financial_cycles',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Cycle.fromRow).toList();
  }

  Future<Cycle?> getCycle(int id) async {
    final rows = await _db.query(
      'financial_cycles',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Cycle.fromRow(rows.first);
  }

  Future<int> insertCycle({
    required String name,
    required Rows? managementRows,
    required Rows? agentRows,
    String? managementSpreadsheetId,
    String? managementSheetName,
    String? agentSpreadsheetId,
    String? agentSheetName,
    double transferDiscountPct = 0,
  }) {
    final now = _now();
    return _db.insert('financial_cycles', {
      'name': name,
      'management_data':
          managementRows == null ? null : jsonEncode(managementRows),
      'agent_data': agentRows == null ? null : jsonEncode(agentRows),
      'management_spreadsheet_id': _str(managementSpreadsheetId),
      'management_sheet_name': _str(managementSheetName),
      'agent_spreadsheet_id': _str(agentSpreadsheetId),
      'agent_sheet_name': _str(agentSheetName),
      'transfer_discount_pct': transferDiscountPct,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Only the provided fields change (like ERP `PUT /cycles/:id`).
  Future<void> updateCycle(int id, Map<String, Object?> fields) async {
    final values = <String, Object?>{};
    fields.forEach((key, value) {
      if (value is List) {
        values[key] = jsonEncode(value);
      } else if (value is String && key.endsWith('_id') ||
          value is String && key.endsWith('_name')) {
        values[key] = _str(value);
      } else {
        values[key] = value;
      }
    });
    values['updated_at'] = _now();
    await _db.update(
      'financial_cycles',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCycle(int id) =>
      _db.delete('financial_cycles', where: 'id = ?', whereArgs: [id]);

  Future<void> setAuditClosed(int id, bool closed) async {
    if (closed) {
      await _db.rawUpdate(
        'UPDATE financial_cycles SET payroll_audit_closed_at = COALESCE(payroll_audit_closed_at, ?), updated_at = ? WHERE id = ?',
        [_now(), _now(), id],
      );
    } else {
      await _db.rawUpdate(
        'UPDATE financial_cycles SET payroll_audit_closed_at = NULL, updated_at = ? WHERE id = ?',
        [_now(), id],
      );
    }
  }

  // -------------------------------------------------------------- settings

  Future<PayrollSettings> getPayrollSettings() async {
    final rows = await _db.query('payroll_settings', where: 'id = 1');
    if (rows.isEmpty) return const PayrollSettings();
    final r = rows.first;
    return PayrollSettings(
      discountRate: (r['discount_rate'] as num?)?.toDouble() ?? 0,
      agentColor: (r['agent_color'] as String?) ?? '#8b5cf6',
      managementColor: (r['management_color'] as String?) ?? '#facc15',
    );
  }

  Future<void> savePayrollSettings(PayrollSettings s) =>
      _db.insert('payroll_settings', {
        'id': 1,
        'discount_rate': s.discountRate,
        'agent_color': s.agentColor,
        'management_color': s.managementColor,
        'updated_at': _now(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  // --------------------------------------------------------------- columns

  Future<CycleColumns> getCycleColumns(int cycleId) async {
    final rows = await _db.query(
      'payroll_cycle_columns',
      where: 'cycle_id = ?',
      whereArgs: [cycleId],
    );
    if (rows.isEmpty) return const CycleColumns();
    final r = rows.first;
    return CycleColumns(
      mgmtUserIdCol: (r['mgmt_user_id_col'] as String?) ?? 'A',
      agentUserIdCol: (r['agent_user_id_col'] as String?) ?? 'A',
      agentSalaryCol: (r['agent_salary_col'] as String?) ?? 'D',
    );
  }

  Future<void> saveCycleColumns(int cycleId, CycleColumns c) =>
      _db.insert('payroll_cycle_columns', {
        'cycle_id': cycleId,
        'mgmt_user_id_col': c.mgmtUserIdCol,
        'agent_user_id_col': c.agentUserIdCol,
        'agent_salary_col': c.agentSalaryCol,
        'updated_at': _now(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  // ----------------------------------------------------------------- cache

  Future<CycleCache?> getCycleCache(int cycleId) async {
    final rows = await _db.query(
      'payroll_cycle_cache',
      where: 'cycle_id = ?',
      whereArgs: [cycleId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    Set<String> ids(Object? v) {
      try {
        final d = jsonDecode((v ?? '[]').toString());
        return d is List ? d.map((e) => e.toString()).toSet() : <String>{};
      } catch (_) {
        return <String>{};
      }
    }

    return CycleCache(
      managementData: decodeRows(r['management_data'] as String?),
      agentData: decodeRows(r['agent_data'] as String?),
      managementSheetName: _str(r['management_sheet_name']),
      agentSheetName: _str(r['agent_sheet_name']),
      auditedAgentIds: ids(r['audited_agent_ids']),
      auditedMgmtIds: ids(r['audited_mgmt_ids']),
      foundInTargetSheetIds: ids(r['found_in_target_sheet_ids']),
      staleAfter: DateTime.tryParse((r['stale_after'] ?? '').toString()),
    );
  }

  Future<void> saveCycleCache(int cycleId, CycleCache c) =>
      _db.insert('payroll_cycle_cache', {
        'cycle_id': cycleId,
        'management_data': jsonEncode(c.managementData),
        'agent_data': jsonEncode(c.agentData),
        'management_sheet_name': c.managementSheetName,
        'agent_sheet_name': c.agentSheetName,
        'audited_agent_ids': jsonEncode(c.auditedAgentIds.toList()),
        'audited_mgmt_ids': jsonEncode(c.auditedMgmtIds.toList()),
        'found_in_target_sheet_ids': jsonEncode(
          c.foundInTargetSheetIds.toList(),
        ),
        'synced_at': _now(),
        'stale_after': c.staleAfter?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---------------------------------------------------------- user status

  Future<void> saveUserAuditStatuses(
    int cycleId,
    List<AuditEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    final byMid = <String, AuditEntry>{};
    for (final e in entries) {
      final mid = e.memberUserId.trim();
      if (mid.isNotEmpty) byMid[mid] = e;
    }
    final batch = _db.batch();
    final now = _now();
    byMid.forEach((mid, e) {
      batch.insert('payroll_user_audit_cache', {
        'cycle_id': cycleId,
        'member_user_id': mid,
        'audit_status': e.status,
        'audit_source': e.source,
        'details_json': e.details == null ? null : jsonEncode(e.details),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  Future<UserAuditStatus?> getUserAuditStatus(
    int cycleId,
    String memberId,
  ) async {
    final rows = await _db.query(
      'payroll_user_audit_cache',
      where: 'cycle_id = ? AND member_user_id = ?',
      whereArgs: [cycleId, memberId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    Map<String, Object?>? details;
    try {
      final d =
          r['details_json'] == null
              ? null
              : jsonDecode(r['details_json'] as String);
      if (d is Map) details = Map<String, Object?>.from(d);
    } catch (_) {}
    return UserAuditStatus(
      (r['audit_status'] as String?) ?? 'غير مدقق',
      r['audit_source'] as String?,
      details,
    );
  }

  Future<Set<String>> auditedMemberIds(int cycleId) async {
    final rows = await _db.query(
      'payroll_user_audit_cache',
      columns: ['member_user_id'],
      where: 'cycle_id = ? AND audit_status = ?',
      whereArgs: [cycleId, 'مدقق'],
    );
    return rows.map((r) => r['member_user_id'].toString()).toSet();
  }

  Future<int> countAudited(int cycleId) async {
    final r = await _db.rawQuery(
      "SELECT COUNT(*) AS n FROM payroll_user_audit_cache WHERE cycle_id = ? AND audit_status = 'مدقق'",
      [cycleId],
    );
    return (r.first['n'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------------------- local workbook

  Future<Map<String, Object?>?> getLocalWorkbook(int cycleId) async {
    final rows = await _db.query(
      'local_workbooks',
      where: 'cycle_id = ?',
      whereArgs: [cycleId],
    );
    if (rows.isEmpty) return null;
    try {
      final d = jsonDecode(rows.first['state_json'] as String);
      return d is Map ? Map<String, Object?>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLocalWorkbook(int cycleId, Map<String, Object?> state) =>
      _db.insert('local_workbooks', {
        'cycle_id': cycleId,
        'state_json': jsonEncode(state),
        'updated_at': _now(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  // ------------------------------------------------------------- run log

  Future<void> addAuditRun(
    int cycleId,
    String mode,
    Map<String, Object?> payload,
  ) => _db.insert('audit_runs', {
    'cycle_id': cycleId,
    'created_at': _now(),
    'mode': mode,
    'payload_json': jsonEncode(payload),
  });

  Future<List<AuditRun>> listAuditRuns(int cycleId, {int limit = 20}) async {
    final rows = await _db.query(
      'audit_runs',
      where: 'cycle_id = ?',
      whereArgs: [cycleId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return [
      for (final r in rows)
        AuditRun(
          id: r['id'] as int,
          cycleId: r['cycle_id'] as int,
          createdAt:
              DateTime.tryParse(r['created_at'] as String) ?? DateTime.now(),
          mode: r['mode'] as String,
          payload: Map<String, Object?>.from(
            jsonDecode(r['payload_json'] as String) as Map,
          ),
        ),
    ];
  }

  // ------------------------------------------------------------------- kv

  Future<String?> getValue(String key) async {
    final rows = await _db.query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setValue(String key, String? value) => _db.insert('kv', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> close() => _db.close();
}
