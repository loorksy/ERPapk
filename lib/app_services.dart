// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';

import 'background/audit_worker.dart';
import 'data/app_database.dart';
import 'data/workspaces.dart';
import 'google/google_auth.dart';
import 'google/sheets_client.dart';
import 'services/audit_job_runner.dart';
import 'services/cycle_service.dart';
import 'services/cycle_sync_worker.dart';
import 'services/payroll_service.dart';
import 'services/search_service.dart';

export 'data/workspaces.dart' show Workspace;

/// The app: the workspaces (owner's request, 2026-11-17) and the Google
/// account they share. Each workspace has its own [AppServices] over its
/// own database; the open one is [active].
class AppHost extends ChangeNotifier {
  AppHost._(this.registry, this.auth, this.sheets);

  static Future<AppHost> open() async {
    final registry = await WorkspaceRegistry.open();
    final auth = GoogleAuth();
    final host = AppHost._(registry, auth, GoogleSheetsApi(auth));
    host._workspaces = await registry.list();
    host._active = await host._servicesFor(await registry.active());
    // Restoring the previous Google session must not block the app.
    auth.restore();
    return host;
  }

  final WorkspaceRegistry registry;
  final GoogleAuth auth;
  final SheetsApi sheets;

  final Map<int, AppServices> _open = {};
  late AppServices _active;
  List<Workspace> _workspaces = const [];

  /// Tab shown after switching workspace (the switch rebuilds the app).
  int initialTab = 1;

  AppServices get active => _active;
  List<Workspace> get workspaces => _workspaces;

  /// Workspaces stay open once used, so an audit running in one keeps
  /// going after switching to another.
  Future<AppServices> _servicesFor(Workspace w) async {
    final open = _open[w.id];
    if (open != null) return open;
    final db = await AppDatabase.open(path: registry.pathOf(w));
    return _open[w.id] = AppServices._(db, auth, sheets, w, this);
  }

  Future<void> switchTo(int id, {int tab = 1}) async {
    if (id == _active.workspace.id) return;
    final w = await registry.get(id);
    if (w == null) return;
    final next = await _servicesFor(w);
    _active.syncWorker.stop();
    await registry.setActive(id);
    initialTab = tab;
    _active = next;
    notifyListeners();
  }

  Future<Workspace> create(String name) async {
    final w = await registry.create(name);
    _workspaces = await registry.list();
    notifyListeners();
    _active._notify();
    return w;
  }

  Future<void> rename(int id, String name) async {
    await registry.rename(id, name);
    _workspaces = await registry.list();
    _open[id]?._rename(_workspaces.firstWhere((w) => w.id == id));
    notifyListeners();
    _active._notify();
  }

  /// Deletes a workspace and everything stored in it on the phone (nothing
  /// is deleted from Google).
  Future<void> delete(int id) async {
    if (id == _active.workspace.id) {
      throw StateError('انتقل إلى مساحة عمل أخرى قبل حذف هذه.');
    }
    final open = _open[id];
    final db = open?.db ?? await _dbOf(id);
    if (db != null && (await db.pendingAuditJobs()).isNotEmpty) {
      if (open == null) await db.close();
      throw StateError(
        'يوجد تدقيق قيد التنفيذ في مساحة العمل هذه. انتظر انتهاءه ثم احذفها.',
      );
    }
    _open.remove(id);
    open?.syncWorker.stop();
    await db?.close();
    await registry.delete(id);
    _workspaces = await registry.list();
    notifyListeners();
    _active._notify();
  }

  Future<AppDatabase?> _dbOf(int id) async {
    final w = await registry.get(id);
    return w == null ? null : AppDatabase.open(path: registry.pathOf(w));
  }

  /// Makes sure unfinished audits of every workspace continue (app opened
  /// or resumed); the Android worker covers them too when the app closes.
  Future<void> resumeAllJobs({bool now = false}) async {
    var any = false;
    for (final w in _workspaces) {
      final s = await _servicesFor(w);
      if ((await s.db.pendingAuditJobs()).isEmpty) continue;
      any = true;
      unawaited(s.jobRunner.runPending());
    }
    if (any) await enqueueAuditWorker(now: now);
  }
}

/// Everything runs on the phone: SQLite storage, the ERP audit engine and a
/// direct Google Sheets connection. One instance per workspace.
class AppServices extends ChangeNotifier {
  AppServices._(this.db, this.auth, this.sheets, Workspace workspace, this.host)
    : _workspace = workspace {
    cycles = CycleService(db, () => sheets);
    payroll = PayrollService(db, () => sheets);
    search = SearchService(db, () => sheets);
    syncWorker = CycleSyncWorker(db, () => sheets);
    auth.changes.listen((_) => notifyListeners());
  }

  void _rename(Workspace w) {
    _workspace = w;
    _notify();
  }

  /// Rebuilds the pages that use this workspace (e.g. the workspace list
  /// changed).
  void _notify() => notifyListeners();

  Workspace _workspace;
  Workspace get workspace => _workspace;
  final AppHost host;

  final AppDatabase db;
  final GoogleAuth auth;
  final SheetsApi sheets;
  late final CycleService cycles;
  late final PayrollService payroll;
  late final SearchService search;
  late final CycleSyncWorker syncWorker;

  /// ERP starts the cycle sync worker with the server; the app runs it
  /// while it is open (see AppShell) when enabled in Settings.
  late final AuditJobRunner jobRunner = AuditJobRunner(db, payroll, cycles);

  /// Saves a Google audit as a job: it starts right away in the app and the
  /// Android worker carries it on if the app is closed.
  Future<int> startAuditJob(
    PayrollRequest request, {
    String kind = JobKind.audit,
    UnmentionedOptions? unmentioned,
  }) async {
    final id = await db.createAuditJob(request.cycleId, {
      ...request.toJson(),
      'kind': kind,
      if (unmentioned != null) 'unmentioned': unmentioned.toJson(),
    });
    await resumeAuditJobs();
    return id;
  }

  /// Makes sure unfinished audits continue (app opened or resumed), in
  /// every workspace.
  Future<void> resumeAuditJobs({bool now = false}) =>
      host.resumeAllJobs(now: now);

  Future<void> resumeBackgroundSync() async {
    if (await syncWorker.isEnabled()) {
      syncWorker.start();
      await syncWorker.runOnce();
    }
  }

  int _columnsRevision = 0;
  int get columnsRevision => _columnsRevision;

  /// Called when the workspace columns are saved in Settings.
  void columnsChanged() {
    _columnsRevision++;
    notifyListeners();
  }

  int _cyclesRevision = 0;
  int get cyclesRevision => _cyclesRevision;

  /// Called whenever a cycle is created, edited, deleted or synced.
  void cyclesChanged() {
    _cyclesRevision++;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppServices> {
  const AppScope({
    super.key,
    required AppServices services,
    required super.child,
  }) : super(notifier: services);

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppServices read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
