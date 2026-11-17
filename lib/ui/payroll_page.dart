// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
import 'ui_kit.dart';
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
  State<PayrollPage> createState() => PayrollPageState();
}

class PayrollPageState extends State<PayrollPage> {
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
      showToast(context, 'اختر فترة الرواتب أولاً', ToastType.error);
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
      'حُمّلت الفترة. اختر مصدر بيانات المستخدمين ثم ابدأ التدقيق.',
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
      showToast(context, 'اختر الفترة أولاً', ToastType.error);
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
    final active = [
      for (final j in await _s.db.pendingAuditJobs())
        if (j.cycleId != null) j,
    ];
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
        'اختر الفترة ومصدر بيانات المستخدمين أولاً',
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
          'اختر ملف بيانات المستخدمين من الجهاز',
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
      // Owner's request: an empty agency name goes to «غير مذكور».
      emptyTitle: _ws.unmentionedLabel,
    );
    _saveDraft();
    return request;
  }

  /// Owner's «غير مذكور» tools: a background job like the audit.
  Future<void> _runTool(String kind) async {
    if (_spreadsheetId == _localSource) {
      showToast(
        context,
        'هذه الأداة تعمل على جداول Google فقط. اختر جدول بيانات المستخدمين من Google.',
        ToastType.warning,
      );
      return;
    }
    if (!(_cycle?.linkedToGoogle ?? false)) {
      showToast(
        context,
        'هذا الإجراء متاح لفترات Google فقط.',
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
      icon: users ? Icons.person_add_alt_outlined : Icons.input_outlined,
      title: users ? 'تدقيق غير المذكورين' : 'سحب صفوف الإدارة إلى «$label»',
      body:
          users
              ? 'سيُضاف كل رقم في ورقة الوكيل غير موجود في جدول بيانات المستخدمين مرة واحدة فقط (حتى لو له أكثر من راتب)، في صف جديد بعد آخر صف: الرقم في العمود $idCols، و«$label» في العمود $labelCols.\n\nثم تُدقق هذه الصفوف بنفس منطق التدقيق: تُنسخ صفوفها من ورقة الإدارة إلى ورقة «$label» (حسب عمود $_userInfoTitleCol)، ويُكتب الراتب والحالة، وتُلوّن. لا تتغير الصفوف الموجودة.'
              : 'ستُنسخ صفوف ورقة الإدارة غير الملوّنة (غير المدققة) التي فيها مبلغ غير صفري في العمود ${ws.mgmtShareCol}، وصاحبها غير موجود في جدول بيانات المستخدمين، إلى ورقة «$label» في جدول الإدارة (تُنشأ إن لم تكن موجودة).\n\nتُلوّن الصفوف المنقولة بلون غير المذكورين (من الإعدادات) في ورقة الإدارة وفي «$label»، حتى تتميز ولا تُسحب مرة أخرى. يُفضّل تنفيذ «تدقيق غير المذكورين» قبلها.',
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
        color: ws.unmentionedColor,
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
    if (result.cycleSynced && !toast.contains('تمت مزامنة جداول الفترة')) {
      toast = 'تمت مزامنة جداول الفترة من Google ثم $toast';
    }
    if (result.duplicates.isNotEmpty) {
      toast +=
          ' — ${result.duplicates.length} رقم مكرر في جدول بيانات المستخدمين (انظر التفاصيل)';
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
            'أرقام مكررة في جدول بيانات المستخدمين: ${duplicates.length}',
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
  //
  // «Compact Fluid UI» (3.0): the audit is one workflow — period → data
  // source → configuration → run → results — with a step indicator. Done
  // steps fold into one line; configuration stays folded until needed.
  // Every control and action of the previous screens is kept.

  /// Re-opens the period choice after the period is loaded.
  bool _editPeriod = false;

  bool get _periodDone => _optionsVisible && _cycleId.isNotEmpty;
  bool get _sourceDone => _periodDone && _spreadsheetId.isNotEmpty;
  bool get _jobRunning => _running || (_job?.active ?? false);

  int get _currentStep {
    if (!_periodDone || _editPeriod) return 0;
    if (_spreadsheetId.isEmpty) return 1;
    if (_jobRunning) return 3;
    if (_result != null) return 4;
    return 3;
  }

  /// From the periods list: select [id] and load it.
  Future<void> openCycle(int id) async {
    if (!_cycles.any((c) => c.id == id)) await _reloadCycles();
    if (!mounted) return;
    setState(() {
      _cycleId = '$id';
      _result = null;
      _editPeriod = false;
    });
    await _refreshSession();
    await _watchJob();
    await _loadCycle();
  }

  @override
  Widget build(BuildContext context) {
    final step = _currentStep;
    return ListView(
      padding: Ds.pagePadding,
      children: [
        Container(
          decoration: panelDecoration(),
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: StepIndicator(
            current: step,
            steps: [
              StepItem('الفترة', done: _periodDone && !_editPeriod),
              StepItem('المصدر', done: _sourceDone),
              StepItem('الإعداد', done: _sourceDone),
              StepItem('التنفيذ', done: _result != null && !_jobRunning),
              StepItem('النتائج', done: _result != null && !_jobRunning),
            ],
          ),
        ),
        gap,
        _periodStep(),
        gap,
        _sourceStep(),
        if (_periodDone) ...[gap, _configStep()],
        gap,
        _runStep(),
        if (_result != null) ...[gap, _resultsStep()],
        if (_periodDone) ...[gap, _toolsBlock()],
      ],
    );
  }

  // ---------------------------------------------------- 1. period

  Widget _periodStep() {
    final cycle = _cycle;
    if (_periodDone && !_editPeriod && cycle != null) {
      final closed = _sessionClosed == true;
      return Container(
        decoration: panelDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListRow(
              title: cycle.name.isEmpty ? 'فترة #${cycle.id}' : cycle.name,
              leading: const IconChip(
                Icons.calendar_month_outlined,
                color: Tw.indigo600,
                bg: Tw.indigo50,
              ),
              subtitle: Text(
                cycle.linkedToGoogle
                    ? 'مرتبطة بـ Google Sheets · تمت المزامنة'
                    : 'من ملفات محلية',
              ),
              trailing: TextButton(
                onPressed: () => setState(() => _editPeriod = true),
                child: const Text('تغيير'),
              ),
            ),
            if (_sessionClosed != null) ...[
              const Divider(height: 1, indent: 14, endIndent: 14),
              ListRow(
                title: closed ? 'التدقيق مُقفل لهذه الفترة' : 'التدقيق مفتوح',
                titleColor: closed ? Tw.slate600 : Tw.slate900,
                leading: Icon(
                  closed ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 20,
                  color: closed ? Tw.slate500 : Tw.amber700,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _setSession(!closed),
                      child: Text(closed ? 'إعادة فتح' : 'إقفال'),
                    ),
                    InfoTip(
                      closed
                          ? 'هذه الفترة مُعلَّمة كمُقفلة على هذا الجهاز. يمكنك إعادة فتح التدقيق للمتابعة، أو متابعة العمل دون تغيير الحالة.'
                          : 'يُحفظ اختيار الفترة والجدول والأعمدة على هذا الجهاز. استخدم «إقفال» عند الانتهاء من تدقيق هذه الفترة.',
                      title: 'حالة التدقيق',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Panel(
      title: 'فترة الرواتب',
      icon: Icons.calendar_month_outlined,
      iconColor: Tw.indigo600,
      iconBg: Tw.indigo50,
      info:
          'اختر فترة الرواتب ثم «تحميل الفترة»: تُزامن جداول الإدارة والوكيل من Google (للفترات المرتبطة) وتظهر خطوات التدقيق.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErpSelect<String>(
            options:
                _cycles.isEmpty
                    ? const [SelectOption('', '— لا توجد فترات —')]
                    : [
                      const SelectOption('', '— اختر الفترة —'),
                      for (final c in _cycles)
                        SelectOption(
                          '${c.id}',
                          c.name.isEmpty ? 'فترة #${c.id}' : c.name,
                        ),
                    ],
            value: _cycleId,
            onChanged: (v) {
              // ERP: changing the period refreshes the session and draft.
              setState(() {
                _cycleId = v;
                _result = null;
              });
              _refreshSession();
              _watchJob();
              _saveDraft();
            },
          ),
          const SizedBox(height: 8),
          ErpButton(
            label: 'تحميل الفترة ومزامنتها',
            loadingLabel: 'جاري التحميل والمزامنة...',
            icon: Icons.cloud_download_outlined,
            loading: _loadingCycle,
            onPressed: () async {
              await _loadCycle();
              if (mounted) setState(() => _editPeriod = false);
            },
          ),
          if (_cycles.isEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: widget.onOpenSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إنشاء فترة رواتب'),
              ),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------- 2. data source

  Widget _sourceStep() {
    if (!_periodDone) {
      return const _LockedStep(
        icon: Icons.grid_on_outlined,
        title: 'مصدر بيانات المستخدمين',
        hint: 'حمّل الفترة أولًا',
      );
    }
    final linked = _cycle?.linkedToGoogle ?? false;
    final isLocal = _spreadsheetId == _localSource;
    return Panel(
      title: 'مصدر بيانات المستخدمين',
      icon: Icons.grid_on_outlined,
      iconColor: Tw.emerald600,
      iconBg: Tw.emerald50,
      info:
          '${isLocal
              ? 'التدقيق يتم على الهاتف، والنتائج تُحفظ في ملف Excel يمكنك تصديره.'
              : linked
              ? 'تُزامن البيانات ثم تُكتب النتائج والألوان في Google؛ الحساب يتم على الهاتف.'
              : 'الفترة من ملفات محلية: التدقيق على Google يحتاج فترة مرتبطة بجداول Google؛ يمكنك التدقيق من ملف على الجهاز.'}\n\nربط Google اختياري: يمكنك اختيار ملف Excel / CSV من الجهاز، أو لصق رابط جدول Google.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErpSelect<String>(
            options: _sourceOptions(),
            value: _spreadsheetId,
            onChanged: _onSourceChanged,
          ),
          if (_ssMessage != null && !_ssMessage!.contains('جاري'))
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('ربط حساب Google من الإعدادات'),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------- 3. configuration

  String _statusColLabel() =>
      _userInfoStatusCol.isEmpty
          ? columnIndexToLetter(
            (columnLetterToIndex(_userInfoSalaryCol) ?? 11) + 1,
          )
          : _userInfoStatusCol;

  Widget _configStep() => CollapsiblePanel(
    title: 'إعداد التدقيق',
    icon: Icons.tune,
    info:
        'ربط حقول البيانات: أعمدة رقم المستخدم والراتب في جدولي الإدارة والوكيل، وورقة بيانات المستخدمين وأعمدتها (رقم المستخدم، اسم الوكالة/الورقة، عمود كتابة الراتب والحالة). القيم الافتراضية من الإعدادات ← ربط حقول البيانات.\n\nنسبة الخصم تُطبَّق على راتب الوكيل، والألوان تُلوَّن بها السجلات المدققة.',
    summary: Row(
      children: [
        Flexible(
          child: SummaryText(
            'الإدارة $_cycleMgmtUserIdCol · الوكيل $_cycleAgentUserIdCol/$_cycleAgentSalaryCol · المستخدم $_userInfoUserIdCol · الراتب $_userInfoSalaryCol · خصم ${_discount.text.trim().isEmpty ? '0' : _discount.text.trim()}%',
          ),
        ),
        ColorDot(hexColor(_agentColor)),
        ColorDot(hexColor(_mgmtColor)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupTitle('جدولا الإدارة والوكيل'),
        Row(
          children: [
            Expanded(
              child: _colSelect(
                'رقم المستخدم (الإدارة)',
                _cycleMgmtCols,
                _cycleMgmtUserIdCol,
                (v) => setState(() => _cycleMgmtUserIdCol = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _colSelect(
                'رقم المستخدم (الوكيل)',
                _cycleAgentCols,
                _cycleAgentUserIdCol,
                (v) => setState(() => _cycleAgentUserIdCol = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _colSelect(
          'الراتب (الوكيل)',
          _cycleAgentCols,
          _cycleAgentSalaryCol,
          (v) => setState(() => _cycleAgentSalaryCol = v),
        ),
        const SizedBox(height: 14),
        const _GroupTitle('بيانات المستخدمين'),
        const FieldHeader('الورقة'),
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
        const SizedBox(height: 8),
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
            const SizedBox(width: 8),
            Expanded(
              child: _colSelect(
                'اسم الوكالة (الورقة)',
                _userInfoCols,
                _userInfoTitleCol,
                (v) => setState(() => _userInfoTitleCol = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldHeader('كتابة الحالة'),
                  ErpSelect<String>(
                    muted: true,
                    options: [
                      SelectOption('', 'تلقائي (${_statusColLabel()})'),
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
        const SizedBox(height: 14),
        const _GroupTitle('نسبة الخصم والألوان'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldHeader('الخصم %'),
                  ErpTextField(
                    controller: _discount,
                    ltr: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _saveDraft();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldHeader('لون الوكيل'),
                  ColorField(
                    value: _agentColor,
                    onChanged: (v) {
                      setState(() => _agentColor = v);
                      _saveDraft();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const FieldHeader('لون الإدارة'),
        ColorField(
          value: _mgmtColor,
          onChanged: (v) {
            setState(() => _mgmtColor = v);
            _saveDraft();
          },
        ),
        const SizedBox(height: 12),
        ErpButton(
          label: 'حفظ كإعداد افتراضي',
          icon: Icons.save_outlined,
          kind: ErpButtonKind.outline,
          height: 42,
          fontSize: 13.5,
          onPressed: _saveSettings,
        ),
      ],
    ),
  );

  Widget _colSelect(
    String label,
    List<ColumnOption> cols,
    String value,
    ValueChanged<String> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldHeader(label),
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

  // -------------------------------------------------------- 4. run

  Widget _runStep() {
    final job = _job;
    final active = job != null && job.active;
    // A follow-up tool shows its progress under the tools.
    if (active && !_toolJob) return _progressCard(job);
    final ready = _sourceDone;
    return Container(
      decoration: panelDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('تنفيذ التدقيق', style: Ds.title)),
              InfoTip(
                _spreadsheetId == _localSource
                    ? 'يُحسب التدقيق على الهاتف من الملف المختار، وتُحفظ النتائج لتصديرها إلى Excel.'
                    : 'مزامنة جداول الفترة وبيانات المستخدمين، ثم مطابقة كل مستخدم برقمه: نسخ سجله إلى ورقة وكالته في جدول الإدارة، كتابة الراتب بعد الخصم والحالة، وتلوين السجلات المطابقة. يعمل في الخلفية ويُستأنف بعد انقطاع الإنترنت.',
                title: 'تنفيذ التدقيق',
              ),
            ],
          ),
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                !_periodDone
                    ? 'حمّل فترة الرواتب واختر مصدر البيانات لبدء التدقيق.'
                    : 'اختر مصدر بيانات المستخدمين لبدء التدقيق.',
                style: Ds.secondary,
              ),
            ),
          ErpButton(
            label: _result == null ? 'بدء التدقيق' : 'إعادة التدقيق',
            icon: Icons.play_arrow_rounded,
            kind: ErpButtonKind.indigo,
            loading: _running,
            loadingLabel: _progress ?? 'جاري التدقيق...',
            onPressed: ready && !_jobRunning ? _runAudit : null,
          ),
        ],
      ),
    );
  }

  /// A running or paused job (audit or one of the follow-up tools).
  Widget _progressCard(AuditJob job) {
    final waiting = job.status == AuditJob.waiting;
    final name = JobKind.title(JobKind.of(job.request));
    final total = job.stepTotal;
    final done = job.stepNext.clamp(0, total);
    final duplicates =
        _jobResultFor == job.id && _jobResult != null
            ? _jobResult!.duplicates
            : const <DuplicateGroup>[];
    return Container(
      decoration: panelDecoration(border: waiting ? Tw.amber200 : null),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProgressRing(
                value: total > 0 ? done / total : null,
                size: 58,
                color: waiting ? Tw.amber500 : Tw.indigo600,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      waiting ? '$name — بانتظار الاتصال' : 'جاري $name…',
                      style: Ds.title,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      job.progress ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Ds.secondary,
                    ),
                    if (total > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        'الخطوة $done من $total',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Tw.slate400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const InfoTip(
                'يمكنك إغلاق التطبيق: يكمل العمل في الخلفية، وإذا انقطع الإنترنت يُستأنف من الخطوة التي توقف عندها (الإضافة، النسخ، الراتب والحالة، التلوين) دون تكرار.',
                title: 'العمل في الخلفية',
              ),
            ],
          ),
          if (waiting) ...[
            const SizedBox(height: 10),
            ErpButton(
              label: 'استئناف الآن',
              icon: Icons.play_arrow_rounded,
              kind: ErpButtonKind.amber,
              height: 40,
              fontSize: 13.5,
              onPressed: _resumeNow,
            ),
          ],
          if (duplicates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _duplicatesBox(duplicates),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------- 5. results

  Widget _resultsStep() {
    final r = _result!;
    final s = r.summary;
    var msg = r.message;
    if (r.cycleSynced && !msg.contains('تمت مزامنة جداول الفترة')) {
      msg = 'تمت مزامنة جداول الفترة من Google ثم $msg';
    }
    final d = r.diagnostic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          'نتائج التدقيق',
          trailing: InfoTip(
            r.localOnly
                ? 'تدقيق على الهاتف فقط — لم تُكتب أي بيانات على Google. صدّر النتائج إلى Excel.'
                : 'النتائج كما كُتبت في Google: النسخ إلى أوراق الوكالات، الراتب والحالة، والتلوين.',
            title: 'نتائج التدقيق',
          ),
        ),
        Container(
          decoration: panelDecoration(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Icon(
                r.applied ? Icons.task_alt : Icons.info_outline,
                size: 20,
                color: r.applied ? Tw.emerald600 : Tw.amber700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: r.applied ? Tw.emerald700 : Tw.amber800,
                    height: 1.5,
                  ),
                ),
              ),
              if (r.localOnly)
                const StatusBadge(
                  'على الهاتف',
                  icon: Icons.smartphone_outlined,
                ),
            ],
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 8),
          GroupList(
            children: [
              MetricRow(
                icon: Icons.groups_outlined,
                label: 'السجلات المدققة',
                value: '${s.total}',
              ),
              MetricRow(
                icon: Icons.verified_outlined,
                label: 'سحب وكالة',
                value: '${s.agent}',
                tone: Tone.accent,
              ),
              MetricRow(
                icon: Icons.apartment_outlined,
                label: 'سحب إدارة',
                value: '${s.management}',
                tone: Tone.warning,
              ),
              MetricRow(
                icon: Icons.person_off_outlined,
                label: 'غير موجود في السجلات',
                value: '${s.notFound}',
                tone: s.notFound > 0 ? Tone.danger : Tone.neutral,
              ),
              if (r.duplicates.isNotEmpty)
                MetricRow(
                  icon: Icons.content_copy_outlined,
                  label: 'سجلات مكررة (حالات استثنائية)',
                  value: '${r.duplicates.length}',
                  tone: Tone.warning,
                ),
            ],
          ),
        ],
        if (r.duplicates.isNotEmpty) ...[
          const SizedBox(height: 8),
          _duplicatesBox(r.duplicates),
        ],
        if (d != null) ...[const SizedBox(height: 8), _diagnosticBox(d)],
        if (r.sampleUserIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          _samplesBox(r),
        ],
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            if (r.spreadsheetUrl != null)
              TextButton.icon(
                onPressed:
                    () => launchUrl(
                      Uri.parse(r.spreadsheetUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                icon: const Icon(Icons.open_in_new, size: 17),
                label: Text(
                  r.summary == null
                      ? 'فتح جدول الإدارة'
                      : 'فتح بيانات المستخدمين',
                ),
              ),
            if (r.localOnly)
              TextButton.icon(
                onPressed: _exporting ? null : _export,
                icon:
                    _exporting
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.ios_share_outlined, size: 17),
                label: const Text('تصدير إلى Excel'),
              ),
          ],
        ),
        Container(
          decoration: panelDecoration(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _detailsList(r.results),
        ),
      ],
    );
  }

  // ----------------------------------------- follow-up actions

  /// Owner's requests (2026-11-17), after a full or partial audit: the
  /// read-only list of agent records not audited yet, then the two
  /// «غير مذكور» steps. Nothing runs until a row is tapped.
  Widget _toolsBlock() {
    final busy = _jobRunning;
    final google = _spreadsheetId != _localSource;
    final label = _ws.unmentionedLabel;
    final toolJob = (_job?.active ?? false) && _toolJob;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          'إجراءات ما بعد التدقيق',
          trailing: const InfoTip(
            'تعمل بعد تدقيق كامل أو جزئي. الإجراءان ١ و٢ يكتبان على Google بعد تأكيد، ويعملان في الخلفية مثل التدقيق، ولجداول Google فقط.',
            title: 'إجراءات ما بعد التدقيق',
          ),
        ),
        GroupList(
          children: [
            ListRow(
              title: 'السجلات غير المدققة في جدول الوكيل',
              subtitle: const Text('للاطلاع فقط · بحث ونسخ'),
              leading: const IconChip(Icons.pending_actions_outlined),
              onTap: _loadingPending ? null : _showUnaudited,
              trailing:
                  _loadingPending
                      ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                      : const RowChevron(),
            ),
            ListRow(
              title: '١. تدقيق غير المذكورين',
              titleColor: busy || !google ? Tw.slate400 : null,
              subtitle: Text(
                'إضافة أرقام الوكيل الناقصة بعنوان «$label» ثم تدقيقها',
              ),
              leading: const IconChip(Icons.person_add_alt_outlined),
              onTap:
                  busy || !google
                      ? null
                      : () => _runTool(JobKind.unmentionedUsers),
              trailing: InfoTip(
                'يضيف أرقام جدول الوكيل غير الموجودة في بيانات المستخدمين (مرة واحدة لكل رقم) في صفوف جديدة بعد آخر صف، بعنوان «$label»، ثم يدققها بنفس منطق التدقيق: تُنسخ إلى ورقة «$label» في جدول الإدارة ويُكتب الراتب والحالة وتُلوّن.',
                title: 'تدقيق غير المذكورين',
              ),
            ),
            ListRow(
              title: '٢. نقل سجلات الإدارة غير الملوّنة',
              titleColor: busy || !google ? Tw.slate400 : null,
              subtitle: Text(
                'التي فيها مبلغ في العمود ${_ws.mgmtShareCol} إلى «$label»',
              ),
              leading: const IconChip(Icons.input_outlined),
              onTap:
                  busy || !google
                      ? null
                      : () => _runTool(JobKind.unmentionedMgmt),
              trailing: InfoTip(
                'ينسخ سجلات الإدارة غير الملوّنة التي فيها مبلغ في العمود ${_ws.mgmtShareCol} فقط، وصاحبها غير موجود في بيانات المستخدمين، إلى ورقة «$label» (تُنشأ إن لم تكن موجودة)، ويلوّنها بلون غير المذكورين من الإعدادات في جدول الإدارة وفي «$label».',
                title: 'نقل سجلات الإدارة غير الملوّنة',
              ),
            ),
          ],
        ),
        if (!google)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'الإجراءان ١ و٢ متاحان لجداول Google فقط.',
              style: TextStyle(fontSize: 12, color: Tw.amber700),
            ),
          ),
        if (toolJob) ...[const SizedBox(height: 8), _progressCard(_job!)],
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
            'عدد الأرقام الفريدة في جدول بيانات المستخدمين: ${d.userInfoUniqueCount}',
            style: t,
          ),
          Text(
            'عدد الأرقام الفريدة في جدول الإدارة (الفترة): ${d.managementUniqueCount}',
            style: t,
          ),
          Text(
            'عدد الأرقام الفريدة في جدول الوكيل (الفترة): ${d.agentUniqueCount}',
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
            'عمود المستخدم في جدول بيانات المستخدمين: ${list(r.sampleUserIds)}',
            style: t,
          ),
          if (r.sampleMgmtIds.isNotEmpty)
            Text(
              'عمود المستخدم في جدول الإدارة (الفترة): ${list(r.sampleMgmtIds)}',
              style: t,
            ),
          if (r.sampleAgentIds.isNotEmpty)
            Text(
              'عمود المستخدم في جدول الوكيل (الفترة): ${list(r.sampleAgentIds)}',
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

/// A small heading inside a folded group.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Tw.indigo700,
      ),
    ),
  );
}

/// A step that is not available yet (greyed, one line).
class _LockedStep extends StatelessWidget {
  const _LockedStep({
    required this.icon,
    required this.title,
    required this.hint,
  });
  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Container(
    decoration: panelDecoration(color: Tw.slate50),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Row(
      children: [
        IconChip(icon, color: Tw.slate400, bg: Colors.white, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Tw.slate400,
            ),
          ),
        ),
        Text(hint, style: const TextStyle(fontSize: 12, color: Tw.slate400)),
      ],
    ),
  );
}
