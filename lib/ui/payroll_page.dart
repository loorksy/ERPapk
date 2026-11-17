// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_services.dart';
import '../data/app_database.dart';
import '../data/file_import.dart';
import '../data/workbook_export.dart';
import '../erp/js_compat.dart';
import '../erp/normalize.dart';
import '../erp/payroll_audit_engine.dart';
import '../google/sheets_client.dart';
import '../services/cycle_service.dart';
import '../services/payroll_service.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'spreadsheet_link.dart';
import 'unaudited_dialog.dart';

const _draftKey = 'payrollAuditDraftV1';
const _localSource = '__local_file__';

/// ERP «تدقيق الرواتب» page (`views/partials/payroll-google.ejs`).
class PayrollPage extends StatefulWidget {
  const PayrollPage({
    super.key,
    required this.active,
    required this.onOpenSheet,
    required this.onOpenSettings,
  });
  final bool active;
  final VoidCallback onOpenSheet;
  final VoidCallback onOpenSettings;

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  bool _ready = false;
  int _revision = -1;
  List<Cycle> _cycles = const [];
  String _cycleId = '';
  bool _optionsVisible = false;
  bool _loadingCycle = false;

  // Session banner
  bool? _sessionClosed;

  // User-info source
  String? _ssMessage = '— جاري التحميل... —';
  List<SpreadsheetFile> _spreadsheets = const [];
  String _spreadsheetId = '';
  ImportedFile? _localFile;
  List<String> _userInfoSheets = const [];
  String _userInfoSheet = '';

  // Columns
  List<ColumnOption> _cycleMgmtCols = CycleService.columnsFromHeader(const []);
  List<ColumnOption> _cycleAgentCols = CycleService.columnsFromHeader(const []);
  List<ColumnOption> _userInfoCols = CycleService.columnsFromHeader(const []);
  String _cycleMgmtUserIdCol = 'A';
  String _cycleAgentUserIdCol = 'A';
  String _cycleAgentSalaryCol = 'D';
  String _userInfoUserIdCol = 'C';
  String _userInfoTitleCol = 'D';
  String _userInfoSalaryCol = 'L';
  String _userInfoStatusCol = '';

  // Settings
  final _discount = TextEditingController(text: '0');
  String _agentColor = defaultAgentColor;
  String _mgmtColor = defaultManagementColor;

  // Run
  bool _running = false;
  String? _progress;
  AuditJob? _job;

  /// Result saved by the running job once prepared (duplicates list),
  /// read once per job instead of on every progress refresh.
  PayrollResult? _jobResult;
  int? _jobResultFor;
  Timer? _poll;
  PayrollResult? _result;
  bool _exporting = false;
  bool _loadingPending = false;

  /// Default columns of the workspace (Settings).
  WorkspaceColumns _ws = const WorkspaceColumns();
  int _columnsRevision = -1;

  AppServices get _s => AppScope.read(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    final connected = services.auth.isConnected;
    if (!_ready) {
      _ready = true;
      _revision = services.cyclesRevision;
      _columnsRevision = services.columnsRevision;
      _connected = connected;
      _init();
      return;
    }
    if (services.columnsRevision != _columnsRevision) {
      // The workspace columns were changed in Settings: use them now.
      _columnsRevision = services.columnsRevision;
      _applyWorkspaceColumns();
    }
    if (services.cyclesRevision != _revision) {
      _revision = services.cyclesRevision;
      _reloadCycles();
    }
    if (connected != _connected) {
      // Google was connected or disconnected from Settings.
      _connected = connected;
      if (_optionsVisible) _loadSpreadsheetsList();
    }
  }

  bool _connected = false;

  @override
  void dispose() {
    _poll?.cancel();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _ws = await _s.db.getWorkspaceColumns();
    await _loadSettings();
    await _loadCycles();
    await _restoreDraft();
    await _refreshSession();
    await _watchJob();
  }

  // ------------------------------------------------------------ settings

  Future<void> _loadSettings() async {
    final s = await _s.db.getPayrollSettings();
    if (!mounted) return;
    setState(() {
      _discount.text = jsNumberToString(s.discountRate);
      _agentColor = s.agentColor;
      _mgmtColor = s.managementColor;
    });
  }

  Future<void> _saveSettings() async {
    final rate = jsParseFloat(_discount.text.trim());
    await _s.db.savePayrollSettings(
      PayrollSettings(
        discountRate: rate.isNaN ? 0 : rate,
        agentColor: _agentColor,
        managementColor: _mgmtColor,
      ),
    );
    if (!mounted) return;
    showToast(context, 'تم حفظ إعدادات التدقيق', ToastType.success);
    _saveDraft();
  }

  // -------------------------------------------------------------- cycles

  Future<void> _loadCycles() async {
    final list = await _s.db.listCycles();
    if (!mounted) return;
    setState(() {
      _cycles = list;
      _cycleId = list.isEmpty ? '' : '${list.first.id}';
    });
  }

  Future<void> _reloadCycles() async {
    final list = await _s.db.listCycles();
    if (!mounted) return;
    setState(() {
      _cycles = list;
      if (!_cycles.any((c) => '${c.id}' == _cycleId)) {
        _cycleId = list.isEmpty ? '' : '${list.first.id}';
        _optionsVisible = false;
        _result = null;
      }
    });
    await _refreshSession();
  }

  Cycle? get _cycle {
    for (final c in _cycles) {
      if ('${c.id}' == _cycleId) return c;
    }
    return null;
  }

  Future<void> _loadCycle() async {
    if (_cycleId.isEmpty) {
      showToast(context, 'اختر دورة مالية أولاً', ToastType.error);
      return;
    }
    setState(() {
      _optionsVisible = true;
      _loadingCycle = true;
    });
    _loadSpreadsheetsList();
    final id = int.parse(_cycleId);
    try {
      final cycle = _cycle;
      if (cycle != null && cycle.linkedToGoogle) {
        final sync = await _s.cycles.syncCycle(id);
        if (mounted && sync.success && sync.detail != null) {
          showToast(
            context,
            '${sync.message} — ${sync.detail}',
            ToastType.success,
          );
        }
        _s.cyclesChanged();
        await _reloadCycles();
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString(), ToastType.warning);
    }
    await _loadCycleColumns();
    await _refreshSession();
    if (!mounted) return;
    setState(() => _loadingCycle = false);
    showToast(
      context,
      'تم تحميل الدورة. اختر جدول البيانات وحدد الأعمدة ثم انقر تدقيق.',
      ToastType.success,
    );
    _saveDraft();
  }

  Future<void> _loadCycleColumns() async {
    if (_cycle == null) return;
    // The list holds light records; the header rows need the snapshot.
    final cycle = await _s.db.getCycle(_cycle!.id);
    if (cycle == null) return;
    // ERP `payrollLoadCycleColumns`: letters up to the widest first row (at
    // least 26), labelled with the header row for Google-linked cycles, and
    // reset to A / A / D.
    final mgmtFirst =
        cycle.managementRows.isEmpty
            ? const <String>[]
            : cycle.managementRows.first;
    final agentFirst =
        cycle.agentRows.isEmpty ? const <String>[] : cycle.agentRows.first;
    final width = [
      26,
      mgmtFirst.length,
      agentFirst.length,
    ].reduce((a, b) => a > b ? a : b);
    final fallback = [
      for (var i = 0; i < width; i++) ColumnOption(columnIndexToLetter(i), ''),
    ];
    if (!mounted) return;
    setState(() {
      _cycleMgmtCols =
          cycle.linkedToGoogle
              ? CycleService.columnsFromHeader(mgmtFirst)
              : fallback;
      _cycleAgentCols =
          cycle.linkedToGoogle
              ? CycleService.columnsFromHeader(agentFirst)
              : fallback;
      _cycleMgmtUserIdCol = _pickCol(_cycleMgmtCols, _ws.mgmtUserIdCol, 'A');
      _cycleAgentUserIdCol = _pickCol(_cycleAgentCols, _ws.agentUserIdCol, 'A');
      _cycleAgentSalaryCol = _pickCol(_cycleAgentCols, _ws.agentSalaryCol, 'D');
    });
  }

  /// Applies the workspace columns (Settings) to every column choice.
  Future<void> _applyWorkspaceColumns() async {
    final ws = await _s.db.getWorkspaceColumns();
    if (!mounted) return;
    setState(() {
      _ws = ws;
      _cycleMgmtUserIdCol = _pickCol(_cycleMgmtCols, ws.mgmtUserIdCol, 'A');
      _cycleAgentUserIdCol = _pickCol(_cycleAgentCols, ws.agentUserIdCol, 'A');
      _cycleAgentSalaryCol = _pickCol(_cycleAgentCols, ws.agentSalaryCol, 'D');
      _userInfoUserIdCol = _pickCol(_userInfoCols, ws.userInfoUserIdCol, 'C');
      _userInfoTitleCol = _pickCol(_userInfoCols, ws.userInfoTitleCol, 'D');
      _userInfoSalaryCol = _pickCol(_userInfoCols, ws.userInfoSalaryCol, 'L');
      _userInfoStatusCol =
          _userInfoCols.any((c) => c.letter == ws.userInfoStatusCol)
              ? ws.userInfoStatusCol
              : '';
    });
    _saveDraft();
  }

  static String _pickCol(
    List<ColumnOption> cols,
    String? wanted,
    String fallback,
  ) {
    if (wanted != null && cols.any((c) => c.letter == wanted)) return wanted;
    if (cols.any((c) => c.letter == fallback)) return fallback;
    return cols.isEmpty ? fallback : cols.first.letter;
  }

  // ------------------------------------------------------------- session

  Future<void> _refreshSession() async {
    final cycle =
        _cycleId.isEmpty ? null : await _s.db.getCycleInfo(int.parse(_cycleId));
    if (!mounted) return;
    setState(
      () => _sessionClosed = cycle == null ? null : cycle.auditClosedAt != null,
    );
  }

  Future<void> _setSession(bool close) async {
    if (_cycleId.isEmpty) {
      showToast(context, 'اختر الدورة أولاً', ToastType.error);
      return;
    }
    await _s.db.setAuditClosed(int.parse(_cycleId), close);
    if (!mounted) return;
    showToast(
      context,
      close ? 'تم إغلاق جلسة التدقيق' : 'تم إعادة فتح جلسة التدقيق',
      ToastType.success,
    );
    _s.cyclesChanged();
    await _refreshSession();
  }

  // ---------------------------------------------------- user-info source

  Future<void> _loadSpreadsheetsList() async {
    setState(() => _ssMessage = '— جاري التحميل... —');
    try {
      final list = await _s.sheets.listSpreadsheets();
      if (!mounted) return;
      setState(() {
        _spreadsheets = [
          ...list,
          for (final f in _spreadsheets)
            if (!list.any((x) => x.id == f.id)) f,
        ];
        _ssMessage = null;
      });
    } catch (e) {
      if (mounted) setState(() => _ssMessage = e.toString());
    }
  }

  List<SelectOption<String>> _sourceOptions() {
    final known = {for (final f in _spreadsheets) f.id};
    return [
      SelectOption('', _ssMessage == null ? '— اختر الجدول —' : _ssMessage!),
      SelectOption(
        _localSource,
        _localFile == null
            ? '📁 ملف من الجهاز (Excel / CSV)…'
            : '📁 ${_localFile!.fileName}',
      ),
      const SelectOption(pasteLinkValue, pasteLinkLabel),
      for (final f in _spreadsheets) SelectOption(f.id, f.name),
      if (_spreadsheetId.isNotEmpty &&
          _spreadsheetId != _localSource &&
          !known.contains(_spreadsheetId))
        SelectOption(_spreadsheetId, _spreadsheetId),
    ];
  }

  Future<void> _onSourceChanged(String picked) async {
    var v = picked;
    if (v == pasteLinkValue) {
      final f = await askSpreadsheetLink(context, _s.sheets);
      if (f == null || !mounted) return;
      setState(() {
        _spreadsheets = [f, ..._spreadsheets.where((x) => x.id != f.id)];
        _ssMessage = null;
      });
      v = f.id;
    }
    if (v == _localSource) {
      try {
        final f = await pickSpreadsheetFile();
        if (!mounted) return;
        if (f == null) {
          if (_localFile == null) setState(() => _spreadsheetId = '');
          return;
        }
        setState(() {
          _localFile = f;
          _spreadsheetId = _localSource;
          _userInfoSheets = f.sheetNames;
          _userInfoSheet = '';
        });
        _applyUserInfoColumns(
          f.firstSheetRows.isEmpty ? const [] : f.firstSheetRows.first,
        );
        _saveDraft();
      } catch (e) {
        if (mounted) showToast(context, e.toString(), ToastType.error);
      }
      return;
    }
    setState(() {
      _spreadsheetId = v;
      _userInfoSheet = '';
      _userInfoSheets = const [];
    });
    if (v.isNotEmpty) await _loadUserInfoSheetsAndColumns(v, null);
    _saveDraft();
  }

  Future<void> _loadUserInfoSheetsAndColumns(
    String spreadsheetId,
    String? sheetName,
  ) async {
    if (spreadsheetId == _localSource) {
      final f = _localFile;
      if (f == null) return;
      final rows = f.rowsOf(sheetName);
      _applyUserInfoColumns(rows.isEmpty ? const [] : rows.first);
      return;
    }
    try {
      final meta = await _s.sheets.getSpreadsheet(spreadsheetId);
      if (!mounted) return;
      setState(() => _userInfoSheets = [for (final s in meta.sheets) s.title]);
      final cols = await _s.cycles.googleColumns(spreadsheetId, sheetName);
      if (!mounted) return;
      _applyColumnOptions(cols);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), ToastType.warning);
    }
  }

  void _applyUserInfoColumns(List<String> header) =>
      _applyColumnOptions(CycleService.columnsFromHeader(header));

  void _applyColumnOptions(List<ColumnOption> cols) {
    setState(() {
      _userInfoCols = cols;
      _userInfoUserIdCol = _pickCol(cols, _ws.userInfoUserIdCol, 'C');
      _userInfoTitleCol = _pickCol(cols, _ws.userInfoTitleCol, 'D');
      _userInfoSalaryCol = _pickCol(cols, _ws.userInfoSalaryCol, 'L');
      _userInfoStatusCol =
          cols.any((c) => c.letter == _ws.userInfoStatusCol)
              ? _ws.userInfoStatusCol
              : '';
    });
  }

  // --------------------------------------------------------------- draft

  Future<void> _saveDraft() async {
    if (_cycleId.isEmpty) return;
    final draft = {
      'cycleId': _cycleId,
      'spreadsheetId': _spreadsheetId == _localSource ? '' : _spreadsheetId,
      'userInfoSheetName': _spreadsheetId == _localSource ? '' : _userInfoSheet,
      'userInfoUserIdCol': _userInfoUserIdCol,
      'userInfoTitleCol': _userInfoTitleCol,
      'userInfoSalaryCol': _userInfoSalaryCol,
      'userInfoStatusCol': _userInfoStatusCol,
      'cycleMgmtUserIdCol': _cycleMgmtUserIdCol,
      'cycleAgentUserIdCol': _cycleAgentUserIdCol,
      'cycleAgentSalaryCol': _cycleAgentSalaryCol,
      'discountRate': _discount.text,
      'agentColor': _agentColor,
      'managementColor': _mgmtColor,
    };
    await _s.db.setValue(_draftKey, jsonEncode(draft));
  }

  Future<void> _restoreDraft() async {
    final raw = await _s.db.getValue(_draftKey);
    if (raw == null || !mounted) return;
    Map<String, dynamic> d;
    try {
      d = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    final cycleId = d['cycleId']?.toString() ?? '';
    if (!_cycles.any((c) => '${c.id}' == cycleId)) return;
    setState(() {
      _cycleId = cycleId;
      _optionsVisible = true;
    });
    await _loadSpreadsheetsList();
    final ss = d['spreadsheetId']?.toString() ?? '';
    if (ss.isNotEmpty) {
      setState(() {
        _spreadsheetId = ss;
        _userInfoSheet = d['userInfoSheetName']?.toString() ?? '';
      });
      await _loadUserInfoSheetsAndColumns(
        ss,
        _userInfoSheet.isEmpty ? null : _userInfoSheet,
      );
    }
    await _loadCycleColumns();
    if (!mounted) return;
    String pick(List<ColumnOption> cols, String key, String current) {
      final v = d[key]?.toString();
      return v != null && cols.any((c) => c.letter == v) ? v : current;
    }

    setState(() {
      _userInfoUserIdCol = pick(
        _userInfoCols,
        'userInfoUserIdCol',
        _userInfoUserIdCol,
      );
      _userInfoTitleCol = pick(
        _userInfoCols,
        'userInfoTitleCol',
        _userInfoTitleCol,
      );
      _userInfoSalaryCol = pick(
        _userInfoCols,
        'userInfoSalaryCol',
        _userInfoSalaryCol,
      );
      final st = d['userInfoStatusCol']?.toString() ?? '';
      _userInfoStatusCol =
          st.isEmpty || _userInfoCols.any((c) => c.letter == st) ? st : '';
      _cycleMgmtUserIdCol = pick(
        _cycleMgmtCols,
        'cycleMgmtUserIdCol',
        _cycleMgmtUserIdCol,
      );
      _cycleAgentUserIdCol = pick(
        _cycleAgentCols,
        'cycleAgentUserIdCol',
        _cycleAgentUserIdCol,
      );
      _cycleAgentSalaryCol = pick(
        _cycleAgentCols,
        'cycleAgentSalaryCol',
        _cycleAgentSalaryCol,
      );
      if (d['discountRate'] != null) {
        _discount.text = d['discountRate'].toString();
      }
      final ac = d['agentColor']?.toString();
      final mc = d['managementColor']?.toString();
      if (ac != null && ac.length == 7) _agentColor = ac;
      if (mc != null && mc.length == 7) _mgmtColor = mc;
    });
  }

  // ----------------------------------------------------------------- run

  /// ERP `payrollRunAudit`: 1/2 sync (cycle + user-info snapshot), then
  /// 2/2 `payroll-execute`. A file from the phone runs the same audit
  /// locally instead.
  Future<void> _runAudit() async {
    final request = await _buildRequest();
    if (request == null || !mounted) return;
    final source = request.userInfo;

    if (source is GoogleUserInfo) {
      // Runs in the background (continues when the app is closed and
      // resumes after a lost connection); this page follows its progress.
      if (!await _noActiveJob()) return;
      await _s.startAuditJob(request);
      if (!mounted) return;
      setState(() => _result = null);
      await _watchJob();
      return;
    }

    setState(() {
      _running = true;
      _progress = 'تدقيق على الهاتف...';
    });
    try {
      final result = await _s.payroll.execute(
        request,
        onProgress: (m) {
          if (mounted) setState(() => _progress = m);
        },
      );
      if (!mounted) return;
      _s.cyclesChanged();
      _announce(result);
      await _refreshSession();
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _progress = null;
        });
      }
    }
  }

  /// One background job at a time (the audit and the «غير مذكور» tools).
  Future<bool> _noActiveJob() async {
    final active = await _s.db.pendingAuditJobs();
    if (!mounted) return false;
    if (active.isEmpty) return true;
    showToast(
      context,
      'يوجد تدقيق قيد التنفيذ. انتظر انتهاءه ثم أعد المحاولة.',
      ToastType.warning,
    );
    await _watchJob();
    return false;
  }

  /// The audit request from the page (cycle, user-info source, columns,
  /// discount and colours); saves the cycle columns like ERP.
  Future<PayrollRequest?> _buildRequest() async {
    if (_cycleId.isEmpty || _spreadsheetId.isEmpty) {
      showToast(
        context,
        'اختر الدورة وجدول معلومات المستخدمين أولاً',
        ToastType.error,
      );
      return null;
    }
    UserInfoSource source;
    if (_spreadsheetId == _localSource) {
      final f = _localFile;
      if (f == null) {
        showToast(
          context,
          'اختر ملف معلومات المستخدمين من الجهاز',
          ToastType.error,
        );
        return null;
      }
      final sheetName =
          _userInfoSheet.isEmpty ? f.sheetNames.first : _userInfoSheet;
      source = LocalUserInfo(f.fileName, sheetName, f.rowsOf(sheetName));
    } else {
      source = GoogleUserInfo(
        _spreadsheetId,
        _userInfoSheet.isEmpty ? null : _userInfoSheet,
      );
    }
    final cycleId = int.parse(_cycleId);
    await _s.db.saveCycleColumns(
      cycleId,
      CycleColumns(
        mgmtUserIdCol: _cycleMgmtUserIdCol,
        agentUserIdCol: _cycleAgentUserIdCol,
        agentSalaryCol: _cycleAgentSalaryCol,
      ),
    );
    if (!mounted) return null;
    final rawDiscount = _discount.text.trim();
    final parsed = rawDiscount.isEmpty ? null : jsParseFloat(rawDiscount);
    final request = PayrollRequest(
      cycleId: cycleId,
      userInfo: source,
      discountRate: parsed == null || parsed.isNaN ? null : parsed,
      agentColor: _agentColor,
      managementColor: _mgmtColor,
      columns: AuditColumns.of(
        userInfoUserIdCol: _userInfoUserIdCol,
        userInfoTitleCol: _userInfoTitleCol,
        userInfoSalaryCol: _userInfoSalaryCol,
        cycleMgmtUserIdCol: _cycleMgmtUserIdCol,
        cycleAgentUserIdCol: _cycleAgentUserIdCol,
        cycleAgentSalaryCol: _cycleAgentSalaryCol,
      ),
      userInfoStatusCol: _userInfoStatusCol.isEmpty ? null : _userInfoStatusCol,
    );
    _saveDraft();
    return request;
  }

  /// Owner's «غير مذكور» tools: a background job like the audit.
  Future<void> _runTool(String kind) async {
    if (_spreadsheetId == _localSource) {
      showToast(
        context,
        'هذه الأداة تعمل على جداول Google فقط. اختر جدول معلومات المستخدمين من Google.',
        ToastType.warning,
      );
      return;
    }
    if (!(_cycle?.linkedToGoogle ?? false)) {
      showToast(
        context,
        'هذه الأداة متاحة لدورات Google فقط.',
        ToastType.warning,
      );
      return;
    }
    final ws = await _s.db.getWorkspaceColumns();
    if (!mounted) return;
    final label = ws.unmentionedLabel;
    final users = kind == JobKind.unmentionedUsers;
    final idCols = {_userInfoUserIdCol, ...ws.unmentionedIdCols}.join(' و');
    final labelCols = {
      _userInfoTitleCol,
      ...ws.unmentionedLabelCols,
    }.where((c) => !ws.unmentionedIdCols.contains(c)).join(' و');
    final ok = await confirmDialog(
      context,
      icon: users ? FontAwesomeIcons.userPlus : FontAwesomeIcons.fileImport,
      title: users ? 'تدقيق غير المذكورين' : 'سحب صفوف الإدارة إلى «$label»',
      body:
          users
              ? 'سيُضاف كل رقم في ورقة الوكيل غير موجود في جدول معلومات المستخدمين مرة واحدة فقط (حتى لو له أكثر من راتب)، في صف جديد بعد آخر صف: الرقم في العمود $idCols، و«$label» في العمود $labelCols.\n\nثم تُدقق هذه الصفوف بنفس منطق التدقيق: تُنسخ صفوفها من ورقة الإدارة إلى ورقة «$label» (حسب عمود $_userInfoTitleCol)، ويُكتب الراتب والحالة، وتُلوّن. لا تتغير الصفوف الموجودة.'
              : 'ستُنسخ صفوف ورقة الإدارة غير الملوّنة (غير المدققة) التي فيها مبلغ غير صفري في العمود ${ws.mgmtShareCol}، وصاحبها غير موجود في جدول معلومات المستخدمين، إلى ورقة «$label» في جدول الإدارة (تُنشأ إن لم تكن موجودة).\n\nتُلوّن الصفوف المنقولة بلون الإدارة حتى لا تُسحب مرة أخرى. يُفضّل تنفيذ «تدقيق غير المذكورين» قبلها.',
      confirmLabel: users ? 'إضافة وتدقيق' : 'سحب الصفوف',
    );
    if (!ok || !mounted) return;
    final request = await _buildRequest();
    if (request == null || !mounted) return;
    if (!await _noActiveJob()) return;
    await _s.startAuditJob(
      request,
      kind: kind,
      unmentioned: UnmentionedOptions(
        label: label,
        idCols: ws.unmentionedIdCols,
        labelCols: ws.unmentionedLabelCols,
        shareCol: ws.mgmtShareCol,
      ),
    );
    if (!mounted) return;
    setState(() => _result = null);
    await _watchJob();
  }

  /// Shows the outcome of an audit like ERP (toast + results section).
  void _announce(PayrollResult result) {
    if (!result.success) {
      showToast(context, result.message, ToastType.error);
      return;
    }
    setState(() => _result = result);
    var toast = result.message;
    if (result.cycleSynced && !toast.contains('تمت مزامنة جداول الدورة')) {
      toast = 'تمت مزامنة جداول الدورة من Google ثم $toast';
    }
    if (result.duplicates.isNotEmpty) {
      toast +=
          ' — ${result.duplicates.length} رقم مكرر في جدول معلومات المستخدمين (انظر التفاصيل)';
    }
    showToast(
      context,
      toast,
      result.applied ? ToastType.success : ToastType.warning,
    );
  }

  // ----------------------------------------------------- background job

  /// Follows the latest audit job of the selected cycle.
  Future<void> _watchJob() async {
    _poll?.cancel();
    if (_cycleId.isEmpty) {
      setState(() => _job = null);
      return;
    }
    final job = await _s.db.latestAuditJob(int.parse(_cycleId));
    if (!mounted) return;
    setState(() => _job = job);
    if (job == null) return;
    if (job.active) {
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _pollJob());
    } else {
      await _settleJob(job);
    }
  }

  Future<void> _pollJob() async {
    final current = _job;
    if (current == null) return;
    final job = await _s.db.getAuditJob(current.id);
    if (!mounted || job == null) return;
    setState(() => _job = job);
    if (job.active && job.stepTotal > 0 && _jobResultFor != job.id) {
      _jobResultFor = job.id;
      final json = await _s.db.getAuditJobResult(job.id);
      if (mounted && json != null) {
        setState(() => _jobResult = PayrollResult.fromJson(json));
      }
    }
    if (!job.active) {
      _poll?.cancel();
      await _settleJob(job);
      _s.cyclesChanged();
      await _refreshSession();
    } else if (job.status == AuditJob.queued &&
        DateTime.now().difference(job.updatedAt).inSeconds > 20) {
      // The worker has not picked the job up yet: make sure it is scheduled.
      await _s.resumeAuditJobs();
    }
  }

  /// A finished job: announce it once, and keep showing its result.
  Future<void> _settleJob(AuditJob job) async {
    final json = await _s.db.getAuditJobResult(job.id);
    if (!mounted) return;
    final result = json == null ? null : PayrollResult.fromJson(json);
    if (!job.seen) {
      await _s.db.updateAuditJob(job.id, {'seen': 1});
      if (!mounted) return;
      if (result != null) {
        _announce(result);
      } else if (job.error != null) {
        showToast(context, job.error!, ToastType.error);
      }
    } else if (result != null && result.success && _result == null) {
      setState(() => _result = result);
    }
  }

  /// The followed job is one of the «غير مذكور» tools (not the audit).
  bool get _toolJob =>
      _job != null && JobKind.of(_job!.request) != JobKind.audit;

  String _busyLabel() {
    final text = _running ? _progress : _job?.progress;
    if (_job?.status == AuditJob.waiting) return 'بانتظار الاتصال...';
    if (text?.startsWith('2/2') == true) return '2/2 تطبيق...';
    if (text?.startsWith('1/2') == true) return '1/2 مزامنة...';
    return 'جاري التدقيق...';
  }

  Widget _jobPanel(AuditJob job) {
    final waiting = job.status == AuditJob.waiting;
    final name = JobKind.title(JobKind.of(job.request));
    final total = job.stepTotal;
    final done = job.stepNext.clamp(0, total);
    final duplicates =
        _jobResultFor == job.id && _jobResult != null
            ? _jobResult!.duplicates
            : const <DuplicateGroup>[];
    return NoticeBox(
      bg: waiting ? Tw.amber50 : Tw.indigo50,
      border: waiting ? Tw.amber200 : Tw.indigo200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FaIcon(
                waiting ? FontAwesomeIcons.wifi : FontAwesomeIcons.rotate,
                size: 13,
                color: waiting ? Tw.amber700 : Tw.indigo600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  waiting
                      ? '$name متوقف مؤقتًا — بانتظار الاتصال'
                      : '$name يعمل في الخلفية',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: waiting ? Tw.amber900 : Tw.indigo900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            job.progress ?? '',
            style: const TextStyle(
              fontSize: 12.5,
              color: Tw.slate700,
              height: 1.5,
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 6,
                backgroundColor: Colors.white,
                color: waiting ? Tw.amber500 : Tw.indigo600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'الخطوة $done من $total',
              style: const TextStyle(fontSize: 11.5, color: Tw.slate500),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'يمكنك إغلاق التطبيق: يكمل العمل في الخلفية، وإذا انقطع الإنترنت يستأنف من الخطوة التي توقف عندها (الإضافة، النسخ، الراتب والحالة، التلوين).',
            style: TextStyle(fontSize: 11.5, color: Tw.slate500, height: 1.6),
          ),
          if (waiting) ...[
            const SizedBox(height: 10),
            ErpButton(
              label: 'استئناف الآن',
              icon: FontAwesomeIcons.play,
              kind: ErpButtonKind.amber,
              height: 40,
              fontSize: 12.5,
              onPressed: _resumeNow,
            ),
          ],
          if (duplicates.isNotEmpty) ...[
            const SizedBox(height: 12),
            _duplicatesBox(duplicates),
          ],
        ],
      ),
    );
  }

  /// Duplicated ids of the user-info sheet: id, rows, and which row counts.
  Widget _duplicatesBox(List<DuplicateGroup> duplicates) {
    const t = TextStyle(fontSize: 12.5, color: Tw.slate700, height: 1.6);
    final shown = duplicates.take(100).toList();
    return NoticeBox(
      bg: Tw.amber50,
      border: Tw.amber200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'أرقام مكررة في جدول معلومات المستخدمين: ${duplicates.length}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Tw.amber800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'دُقق أول صف لكل رقم ونُسخ مرة واحدة فقط؛ الصفوف الأخرى كُتب فيها «مكرر» ولم تُنسخ.',
            style: TextStyle(fontSize: 11.5, color: Tw.amber900, height: 1.5),
          ),
          const SizedBox(height: 8),
          for (final d in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  style: t,
                  children: [
                    TextSpan(
                      text: d.userId,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text:
                          ' — الصفوف: ${d.rows.join('، ')} (دُقق الصف ${d.firstRow})',
                    ),
                  ],
                ),
              ),
            ),
          if (duplicates.length > shown.length)
            Text(
              '… و${duplicates.length - shown.length} رقم آخر',
              style: const TextStyle(fontSize: 11.5, color: Tw.slate500),
            ),
        ],
      ),
    );
  }

  /// Owner's request: agent-sheet ids not audited yet, on demand (read only).
  Future<void> _showUnaudited() async {
    if (_cycleId.isEmpty) return;
    setState(() => _loadingPending = true);
    try {
      final data = await _s.payroll.unauditedAgentMembers(int.parse(_cycleId));
      if (!mounted) return;
      await showUnauditedDialog(context, data);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), ToastType.error);
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  Future<void> _resumeNow() async {
    await _s.resumeAuditJobs(now: true);
    if (mounted) showToast(context, 'جاري استئناف التدقيق...', ToastType.info);
  }

  Future<void> _export() async {
    final cycle =
        _cycleId.isEmpty ? null : await _s.db.getCycle(int.parse(_cycleId));
    if (cycle == null) return;
    setState(() => _exporting = true);
    try {
      final state = LocalWorkbookState.fromJson(
        await _s.db.getLocalWorkbook(cycle.id),
      );
      final bytes = WorkbookExport.encode(cycle, state);
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final safeName = cycle.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نتائج التدقيق',
        fileName: 'تدقيق $safeName - $date.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (saved != null && mounted) {
        showToast(context, 'تم حفظ ملف Excel', ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'تعذر تصدير النتائج: $e', ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
    children: [
      ErpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cycleSection(),
            if (_optionsVisible) _optionsSection(),
            _settingsSection(),
            if (_optionsVisible && _cycleId.isNotEmpty) _toolsSection(),
            if (_result != null) _resultsSection(),
          ],
        ),
      ),
    ],
  );

  Widget _cycleSection() => CardSection(
    top: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('الدورة المالية'),
        ErpSelect<String>(
          options:
              _cycles.isEmpty
                  ? const [SelectOption('', '— لا توجد دورات —')]
                  : [
                    const SelectOption('', '— اختر الدورة —'),
                    for (final c in _cycles)
                      SelectOption(
                        '${c.id}',
                        c.name.isEmpty ? 'دورة #${c.id}' : c.name,
                      ),
                  ],
          value: _cycleId,
          onChanged: (v) {
            // ERP: changing the cycle refreshes the session and the draft.
            setState(() {
              _cycleId = v;
              _result = null;
            });
            _refreshSession();
            _watchJob();
            _saveDraft();
          },
        ),
        const SizedBox(height: 12),
        ErpButton(
          label: 'تحميل الدورة',
          loadingLabel: 'جاري التحميل والمزامنة...',
          icon: FontAwesomeIcons.cloudArrowDown,
          loading: _loadingCycle,
          onPressed: _loadCycle,
        ),
        if (_cycles.isEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: widget.onOpenSheet,
            child: const NoticeBox(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'لا توجد دورات. أنشئ دورة من قسم Sheet أولاً.',
                style: TextStyle(fontSize: 12, color: Tw.slate600),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _optionsSection() {
    final linked = _cycle?.linkedToGoogle ?? false;
    final isLocal = _spreadsheetId == _localSource;
    return CardSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sessionClosed != null) ...[
            _sessionBanner(),
            const SizedBox(height: 24),
          ],
          const FieldLabel('جدول معلومات المستخدمين'),
          ErpSelect<String>(
            options: _sourceOptions(),
            value: _spreadsheetId,
            onChanged: _onSourceChanged,
          ),
          if (_ssMessage != null && !_ssMessage!.contains('جاري')) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: widget.onOpenSettings,
              child: const Text(
                'ربط Google اختياري: يمكنك التدقيق من ملف على الجهاز، أو اربط الحساب من الإعدادات.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Tw.indigo600,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ErpButton(
            label: 'تدقيق',
            icon: FontAwesomeIcons.clipboardCheck,
            kind: ErpButtonKind.emerald,
            loading: _running || (_job?.active ?? false),
            loadingLabel: _busyLabel(),
            onPressed: _runAudit,
          ),
          if (_running && _progress != null) ...[
            const SizedBox(height: 8),
            Text(
              _progress!,
              style: const TextStyle(fontSize: 12, color: Tw.slate500),
            ),
          ],
          if ((_job?.active ?? false) && !_toolJob) ...[
            const SizedBox(height: 12),
            _jobPanel(_job!),
          ],
          const SizedBox(height: 6),
          Text(
            isLocal
                ? 'التدقيق يتم على الهاتف، والنتائج تُحفظ في ملف Excel يمكنك تصديره.'
                : linked
                ? 'مزامنة اللقطات ثم كتابة النتائج والألوان في Google — التدقيق يُحسب على الهاتف.'
                : 'الدورة من ملفات محلية: التدقيق على Google يحتاج دورة مرتبطة بجداول Google كما في النظام؛ يمكنك التدقيق من ملف على الجهاز.',
            style: const TextStyle(
              fontSize: 11.5,
              color: Tw.slate500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          const SectionCaption('أعمدة الدورة (الإدارة والوكيل)'),
          _colSelect(
            'رقم المستخدم — الإدارة',
            _cycleMgmtCols,
            _cycleMgmtUserIdCol,
            (v) => setState(() => _cycleMgmtUserIdCol = v),
          ),
          const SizedBox(height: 12),
          _colSelect(
            'رقم المستخدم — الوكيل',
            _cycleAgentCols,
            _cycleAgentUserIdCol,
            (v) => setState(() => _cycleAgentUserIdCol = v),
          ),
          const SizedBox(height: 12),
          _colSelect(
            'الراتب — الوكيل',
            _cycleAgentCols,
            _cycleAgentSalaryCol,
            (v) => setState(() => _cycleAgentSalaryCol = v),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(height: 1, color: Tw.slate100),
          ),
          const SectionCaption('ورقة وجدول معلومات المستخدمين'),
          const FieldLabel('الورقة', small: true),
          ErpSelect<String>(
            muted: true,
            options: [
              const SelectOption('', 'أول ورقة'),
              for (final s in _userInfoSheets) SelectOption(s, s),
              if (_userInfoSheet.isNotEmpty &&
                  !_userInfoSheets.contains(_userInfoSheet))
                SelectOption(_userInfoSheet, _userInfoSheet),
            ],
            value: _userInfoSheet,
            onChanged: (v) {
              setState(() => _userInfoSheet = v);
              if (_spreadsheetId.isNotEmpty) {
                _loadUserInfoSheetsAndColumns(
                  _spreadsheetId,
                  v.isEmpty ? null : v,
                );
              }
              _saveDraft();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _colSelect(
                  'رقم المستخدم',
                  _userInfoCols,
                  _userInfoUserIdCol,
                  (v) => setState(() => _userInfoUserIdCol = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _colSelect(
                  'اسم الورقة',
                  _userInfoCols,
                  _userInfoTitleCol,
                  (v) => setState(() => _userInfoTitleCol = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _colSelect(
                  'كتابة الراتب',
                  _userInfoCols,
                  _userInfoSalaryCol,
                  (v) => setState(() => _userInfoSalaryCol = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FieldLabel('الحالة (محاذي)', small: true),
                    ErpSelect<String>(
                      muted: true,
                      options: [
                        SelectOption(
                          '',
                          'تلقائي (${columnIndexToLetter((columnLetterToIndex(_userInfoSalaryCol) ?? 11) + 1)})',
                        ),
                        for (final c in _userInfoCols)
                          SelectOption(c.letter, c.label),
                      ],
                      value: _userInfoStatusCol,
                      onChanged: (v) {
                        setState(() => _userInfoStatusCol = v);
                        _saveDraft();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colSelect(
    String label,
    List<ColumnOption> cols,
    String value,
    ValueChanged<String> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(label, small: true),
      ErpSelect<String>(
        muted: true,
        options: [for (final c in cols) SelectOption(c.letter, c.label)],
        value: value,
        onChanged: (v) {
          onChanged(v);
          _saveDraft();
        },
      ),
    ],
  );

  Widget _sessionBanner() {
    final closed = _sessionClosed == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xccfffbeb),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Tw.amber200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            closed ? 'تم إغلاق التدقيق' : 'التدقيق نشط لهذه الدورة',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Tw.amber950,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            closed
                ? 'هذه الدورة مُعلَّمة كمغلقة على هذا الجهاز. يمكنك إعادة فتح الجلسة للمتابعة، أو متابعة العمل بدون تغيير الحالة.'
                : 'يُحفظ اختيار الدورة والجدول والأعمدة في هذا الجهاز. استخدم «إغلاق التدقيق» عند الانتهاء من العمل على هذه الدورة.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Tw.amber900,
            ),
          ),
          const SizedBox(height: 12),
          ErpButton(
            label: closed ? 'إعادة فتح الجلسة' : 'إغلاق التدقيق',
            kind: closed ? ErpButtonKind.slate : ErpButtonKind.amber,
            height: 40,
            fontSize: 12,
            onPressed: () => _setSession(!closed),
          ),
          if (closed) ...[
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Divider(height: 1, color: Tw.amber200),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                FaIcon(
                  FontAwesomeIcons.circleCheck,
                  size: 14,
                  color: Tw.emerald800,
                ),
                SizedBox(width: 6),
                Text(
                  'تم إغلاق جلسة التدقيق لهذه الدورة.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Tw.emerald800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Owner's requests (2026-11-17), after a full or partial audit: the
  /// read-only list of agent users not audited yet, then the two
  /// «غير مذكور» steps. Nothing is shown until a button is pressed.
  Widget _toolsSection() {
    final busy = _running || (_job?.active ?? false);
    final google = _spreadsheetId != _localSource;
    final label = _ws.unmentionedLabel;
    Widget hint(String text) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.5, color: Tw.slate500, height: 1.6),
      ),
    );
    return CardSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCaption('أدوات بعد التدقيق'),
          ErpButton(
            label: 'عرض غير المدققين في ورقة الوكيل',
            icon: FontAwesomeIcons.userClock,
            kind: ErpButtonKind.outline,
            loading: _loadingPending,
            loadingLabel: 'جاري التحميل...',
            height: 42,
            fontSize: 13,
            onPressed: _showUnaudited,
          ),
          hint('قائمة للقراءة فقط: الرقم والاسم والعدد المتبقي، مع النسخ.'),
          ErpButton(
            label: '١. تدقيق غير المذكورين',
            icon: FontAwesomeIcons.userPlus,
            kind: ErpButtonKind.indigoSoft,
            height: 42,
            fontSize: 13,
            onPressed:
                busy || !google
                    ? null
                    : () => _runTool(JobKind.unmentionedUsers),
          ),
          hint(
            'يضيف أرقام ورقة الوكيل غير الموجودة في جدول معلومات المستخدمين (مرة واحدة لكل رقم) بعنوان «$label» ثم يدققها بنفس المنطق.',
          ),
          ErpButton(
            label: '٢. سحب صفوف الإدارة غير الملوّنة إلى «$label»',
            icon: FontAwesomeIcons.fileImport,
            kind: ErpButtonKind.indigoSoft,
            height: 42,
            fontSize: 13,
            onPressed:
                busy || !google
                    ? null
                    : () => _runTool(JobKind.unmentionedMgmt),
          ),
          hint(
            'ينسخ صفوف الإدارة غير الملوّنة التي فيها مبلغ في العمود ${_ws.mgmtShareCol} فقط إلى ورقة «$label» (تُنشأ إن لم تكن موجودة).',
          ),
          if (!google)
            const Text(
              'الأداتان ١ و٢ تعملان على جداول Google فقط.',
              style: TextStyle(fontSize: 11.5, color: Tw.amber700),
            ),
          if ((_job?.active ?? false) && _toolJob) _jobPanel(_job!),
        ],
      ),
    );
  }

  Widget _settingsSection() => CardSection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionCaption('الخصم والألوان'),
        const FieldLabel('نسبة الخصم (%)'),
        ErpTextField(
          controller: _discount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _saveDraft(),
        ),
        const SizedBox(height: 16),
        const FieldLabel('لون الوكيل'),
        ColorField(
          value: _agentColor,
          onChanged: (v) {
            setState(() => _agentColor = v);
            _saveDraft();
          },
        ),
        const SizedBox(height: 16),
        const FieldLabel('لون الإدارة'),
        ColorField(
          value: _mgmtColor,
          onChanged: (v) {
            setState(() => _mgmtColor = v);
            _saveDraft();
          },
        ),
        const SizedBox(height: 16),
        ErpButton(
          label: 'حفظ الإعدادات',
          icon: FontAwesomeIcons.floppyDisk,
          kind: ErpButtonKind.outline,
          height: 40,
          onPressed: _saveSettings,
        ),
      ],
    ),
  );

  Widget _resultsSection() => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Tw.slate200)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Tw.slate50,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: const Text(
            'نتيجة التدقيق',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Tw.slate800,
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.all(20), child: _resultContent()),
      ],
    ),
  );

  Widget _resultContent() {
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    final s = r.summary;
    var msg = r.message;
    if (r.cycleSynced && !msg.contains('تمت مزامنة جداول الدورة')) {
      msg = 'تمت مزامنة جداول الدورة من Google ثم $msg';
    }
    const base = TextStyle(fontSize: 14, color: Tw.slate600, height: 1.6);
    Widget li(String label, int v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: '$v',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Tw.slate800,
              ),
            ),
          ],
        ),
      ),
    );
    final d = r.diagnostic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.localOnly)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                FaIcon(
                  FontAwesomeIcons.mobileScreen,
                  size: 11,
                  color: Tw.slate500,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'تدقيق على الهاتف فقط — لم تُكتب أي بيانات على Google.',
                    style: TextStyle(fontSize: 12, color: Tw.slate500),
                  ),
                ),
              ],
            ),
          ),
        Text(
          msg,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: r.applied ? Tw.emerald700 : Tw.amber700,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        if (s != null) ...[
          li('إجمالي الصفوف', s.total),
          li('سحب وكالة', s.agent),
          li('سحب إدارة', s.management),
          li('غير موجود', s.notFound),
        ],
        if (r.duplicates.isNotEmpty) ...[
          const SizedBox(height: 12),
          _duplicatesBox(r.duplicates),
        ],
        if (d != null) ...[const SizedBox(height: 12), _diagnosticBox(d)],
        if (r.sampleUserIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          _samplesBox(r),
        ],
        if (r.spreadsheetUrl != null) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap:
                () => launchUrl(
                  Uri.parse(r.spreadsheetUrl!),
                  mode: LaunchMode.externalApplication,
                ),
            child: Text(
              r.summary == null
                  ? 'فتح جدول الإدارة في Google ←'
                  : 'فتح جدول معلومات المستخدمين في Google ←',
              style: TextStyle(
                fontSize: 14,
                color: Tw.indigo600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
        if (r.localOnly) ...[
          const SizedBox(height: 10),
          ErpButton(
            label: 'تصدير النتائج إلى Excel',
            icon: FontAwesomeIcons.fileExport,
            kind: ErpButtonKind.indigoSoft,
            loading: _exporting,
            loadingLabel: 'جاري التصدير...',
            onPressed: _export,
          ),
        ],
        const SizedBox(height: 12),
        _detailsList(r.results),
      ],
    );
  }

  Widget _diagnosticBox(PayrollDiagnostic d) {
    const t = TextStyle(fontSize: 13.5, color: Tw.slate700, height: 1.6);
    String? hint;
    if (d.managementUniqueCount == 0 && d.agentUniqueCount == 0) {
      hint =
          'عمودا الإدارة والوكيل لا يقرآن أرقاماً — غيّر «رقم المستخدم — الإدارة» و«رقم المستخدم — الوكيل» إلى العمود الذي فيه رقم المستخدم فعلياً (B, C, D...).';
    } else if (d.managementUniqueCount == 0) {
      hint =
          'المشكلة من جدول الإدارة: لم يُقرأ أي رقم من ورقة الإدارة (العدد 0). غيّر «رقم المستخدم — الإدارة» إلى العمود الذي فيه رقم المستخدم فعلياً (جرّب B ثم C ثم D…). الوكيل يقرأ بشكل صحيح.';
    } else if (d.agentUniqueCount == 0) {
      hint =
          'المشكلة من جدول الوكيل: لم يُقرأ أي رقم من ورقة الوكيل. غيّر «رقم المستخدم — الوكيل» إلى العمود الصحيح (B, C, D…).';
    }
    return NoticeBox(
      bg: Tw.amber50,
      border: Tw.amber200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تشخيص عند عدم التطابق:',
            style: TextStyle(fontWeight: FontWeight.w700, color: Tw.amber800),
          ),
          const SizedBox(height: 6),
          Text(
            'عدد الأرقام الفريدة في جدول معلومات المستخدمين: ${d.userInfoUniqueCount}',
            style: t,
          ),
          Text(
            'عدد الأرقام الفريدة في جدول الإدارة (الدورة): ${d.managementUniqueCount}',
            style: t,
          ),
          Text(
            'عدد الأرقام الفريدة في جدول الوكيل (الدورة): ${d.agentUniqueCount}',
            style: t,
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 13.5,
                color: Tw.amber700,
                fontWeight: FontWeight.w500,
                height: 1.6,
              ),
            ),
          ],
          if (d.sampleCheck.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'تحقق من أول 5 أرقام من جدول المستخدمين:',
              style: TextStyle(fontWeight: FontWeight.w500, color: Tw.slate700),
            ),
            for (final sc in d.sampleCheck)
              Text(
                '${sc.userId}: في الإدارة ${sc.inMgmt ? 'نعم' : 'لا'}، في الوكيل ${sc.inAgent ? 'نعم' : 'لا'}',
                style: t,
              ),
          ],
        ],
      ),
    );
  }

  Widget _samplesBox(PayrollResult r) {
    String list(List<String> ids) =>
        ids.take(10).join(', ') + (ids.length > 10 ? '...' : '');
    const t = TextStyle(fontSize: 13.5, color: Tw.slate600, height: 1.6);
    return NoticeBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'عينة أرقام للمقارنة (للمراجعة عند عدم التطابق):',
            style: TextStyle(fontWeight: FontWeight.w500, color: Tw.slate700),
          ),
          const SizedBox(height: 6),
          Text(
            'عمود المستخدم في جدول معلومات المستخدمين: ${list(r.sampleUserIds)}',
            style: t,
          ),
          if (r.sampleMgmtIds.isNotEmpty)
            Text(
              'عمود المستخدم في جدول الإدارة (الدورة): ${list(r.sampleMgmtIds)}',
              style: t,
            ),
          if (r.sampleAgentIds.isNotEmpty)
            Text(
              'عمود المستخدم في جدول الوكيل (الدورة): ${list(r.sampleAgentIds)}',
              style: t,
            ),
        ],
      ),
    );
  }

  Widget _detailsList(List<AuditResultRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    Color tone(String type) =>
        isAgentType(type)
            ? hexColor(_agentColor)
            : type == typeManagement
            ? hexColor(_mgmtColor)
            : Tw.slate300;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          'عرض النتيجة لكل مستخدم (${rows.length})',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Tw.indigo700,
          ),
        ),
        children: [
          SizedBox(
            height: rows.length > 8 ? 360 : null,
            child: ListView.separated(
              shrinkWrap: true,
              physics:
                  rows.length > 8 ? null : const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder:
                  (_, _) => const Divider(height: 1, color: Tw.slate100),
              itemBuilder: (_, i) {
                final r = rows[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: tone(r.type),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.userId.isEmpty ? '—' : r.userId,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Tw.slate800,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Tw.slate600,
                          ),
                        ),
                      ),
                      Text(
                        r.type,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Tw.slate500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
