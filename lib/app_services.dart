// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'google/google_auth.dart';
import 'google/sheets_client.dart';
import 'services/cycle_service.dart';
import 'services/cycle_sync_worker.dart';
import 'services/payroll_service.dart';
import 'services/search_service.dart';

/// Everything runs on the phone: SQLite storage, the ERP audit engine and a
/// direct Google Sheets connection.
class AppServices extends ChangeNotifier {
  AppServices._(this.db, this.auth, this.sheets) {
    cycles = CycleService(db, () => sheets);
    payroll = PayrollService(db, () => sheets);
    search = SearchService(db, () => sheets);
    syncWorker = CycleSyncWorker(db, () => sheets);
    auth.changes.listen((_) => notifyListeners());
  }

  static Future<AppServices> open() async {
    final db = await AppDatabase.open();
    final auth = GoogleAuth();
    final services = AppServices._(db, auth, GoogleSheetsApi(auth));
    // Restoring the previous Google session must not block the app.
    auth.restore();
    return services;
  }

  final AppDatabase db;
  final GoogleAuth auth;
  final SheetsApi sheets;
  late final CycleService cycles;
  late final PayrollService payroll;
  late final SearchService search;
  late final CycleSyncWorker syncWorker;

  /// ERP starts the cycle sync worker with the server; the app runs it
  /// while it is open (see AppShell) when enabled in Settings.
  Future<void> resumeBackgroundSync() async {
    if (await syncWorker.isEnabled()) {
      syncWorker.start();
      await syncWorker.runOnce();
    }
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
