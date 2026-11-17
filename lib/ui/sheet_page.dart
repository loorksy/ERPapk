// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/app_database.dart';
import '../data/file_import.dart';
import '../erp/js_compat.dart';
import '../google/sheets_client.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'spreadsheet_link.dart';
import 'ui_kit.dart';

const _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

String formatArabicDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// «فترات الرواتب» (ERP «Sheet»): the payroll periods — each one a pair of
/// management and agent sheets — with a summary, compact rows, their audit
/// status and a context menu. The create window is [CycleModal].
class SheetPage extends StatefulWidget {
  const SheetPage({super.key, this.onAudit});

  /// Opens the audit of a period (bottom navigation «التدقيق»).
  final ValueChanged<int>? onAudit;

  @override
  State<SheetPage> createState() => SheetPageState();
}

/// Audit state of a period shown on its row.
enum PeriodState { pending, running, audited, closed, failed }

class SheetPageState extends State<SheetPage> {
  List<Cycle>? _cycles;
  Map<int, PeriodState> _states = const {};
  int _revision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (services.cyclesRevision != _revision) {
      _revision = services.cyclesRevision;
      _load();
    }
  }

  Future<void> _load() async {
    final db = AppScope.read(context).db;
    final list = await db.listCycles();
    final states = <int, PeriodState>{};
    for (final c in list) {
      final job = await db.latestAuditJob(c.id);
      states[c.id] =
          job != null && job.active
              ? PeriodState.running
              : c.auditClosedAt != null
              ? PeriodState.closed
              : job?.status == AuditJob.done
              ? PeriodState.audited
              : job?.status == AuditJob.failed
              ? PeriodState.failed
              : PeriodState.pending;
    }
    if (mounted) {
      setState(() {
        _cycles = list;
        _states = states;
      });
    }
  }

  /// The «+» of the top bar.
  void openCreate() => _openModal();

  Future<void> _openModal([Cycle? edit]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: CycleModal(edit: edit),
          ),
    );
    if (saved == true && mounted) AppScope.read(context).cyclesChanged();
  }

  Future<void> _confirmDelete(Cycle c) async {
    final ok = await confirmDialog(
      context,
      icon: Icons.delete_outline,
      iconColor: Tw.red600,
      iconBg: Tw.red50,
      title: 'حذف فترة الرواتب',
      body:
          'سيُحذف «${c.name}» من هذا الجهاز مع حالات تدقيقها. لا يُحذف أي شيء من Google، ولا يمكن التراجع.',
      confirmLabel: 'حذف',
      confirmKind: ErpButtonKind.danger,
    );
    if (!ok || !mounted) return;
    await AppScope.read(context).cycles.deleteCycle(c.id);
    if (!mounted) return;
    showToast(context, 'حُذفت فترة الرواتب', ToastType.success);
    AppScope.read(context).cyclesChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cycles = _cycles;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: Ds.pagePadding,
        children: [
          if (cycles == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (cycles.isEmpty)
            EmptyState(
              icon: Icons.calendar_month_outlined,
              leading: Image.asset(
                'assets/brand/logo.png',
                width: 56,
                height: 56,
              ),
              title: 'مرحبًا بك في المدقق',
              message:
                  'ابدأ بإنشاء فترة رواتب: اربط جدول الإدارة وجدول الوكيل من Google Sheets أو من ملفات Excel / CSV، ثم دقّق الرواتب عليها.',
              action: ErpButton(
                label: 'إنشاء فترة رواتب',
                icon: Icons.add,
                expand: false,
                onPressed: _openModal,
              ),
            )
          else ...[
            _summary(cycles),
            const SizedBox(height: 14),
            SectionLabel(
              'الفترات',
              trailing: InfoTip(
                'كل فترة رواتب تجمع جدول الإدارة وجدول الوكيل (من Google Sheets أو من ملفات). اضغط الفترة لتدقيقها، ومن القائمة ⋮ يمكن تعديلها أو حذفها. اسحب للأسفل للتحديث.',
                title: 'فترات الرواتب',
              ),
            ),
            GroupList(children: [for (final c in cycles) _row(c)]),
          ],
        ],
      ),
    );
  }

  Widget _summary(List<Cycle> cycles) {
    int count(PeriodState s) => _states.values.where((x) => x == s).length;
    final linked = cycles.where((c) => c.linkedToGoogle).length;
    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'إجمالي الفترات',
            value: '${cycles.length}',
            icon: Icons.layers_outlined,
            color: Tw.indigo600,
            selected: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatTile(
            label: 'قيد التنفيذ',
            value: '${count(PeriodState.running)}',
            icon: Icons.sync,
            color: Tw.slate700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatTile(
            label: 'مدققة',
            value: '${count(PeriodState.audited) + count(PeriodState.closed)}',
            icon: Icons.task_alt,
            color: Tw.emerald600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatTile(
            label: 'Google Sheets',
            value: '$linked',
            icon: Icons.cloud_done_outlined,
            color: Tw.slate700,
          ),
        ),
      ],
    );
  }

  StatusBadge _badge(PeriodState s) => switch (s) {
    PeriodState.running => const StatusBadge(
      'قيد التنفيذ',
      tone: Tone.accent,
      icon: Icons.sync,
    ),
    PeriodState.audited => const StatusBadge(
      'مدققة',
      tone: Tone.success,
      icon: Icons.check,
    ),
    PeriodState.closed => const StatusBadge(
      'مُقفلة',
      tone: Tone.neutral,
      icon: Icons.lock_outline,
    ),
    PeriodState.failed => const StatusBadge(
      'تعذّر التدقيق',
      tone: Tone.danger,
      icon: Icons.error_outline,
    ),
    PeriodState.pending => const StatusBadge(
      'بانتظار التدقيق',
      tone: Tone.warning,
      icon: Icons.schedule,
    ),
  };

  Widget _row(Cycle c) {
    final state = _states[c.id] ?? PeriodState.pending;
    return ListRow(
      title: c.name.isEmpty ? 'فترة #${c.id}' : c.name,
      onTap: widget.onAudit == null ? null : () => widget.onAudit!(c.id),
      leading: IconChip(
        Icons.table_chart_outlined,
        size: 36,
        color: c.linkedToGoogle ? Tw.emerald600 : Tw.slate600,
        bg: c.linkedToGoogle ? Tw.emerald50 : Tw.slate100,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(formatArabicDate(c.createdAt)),
            const Text('·'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorDot(
                  c.linkedToGoogle ? Tw.emerald500 : Tw.amber500,
                  size: 8,
                ),
                const SizedBox(width: 4),
                Text(c.linkedToGoogle ? 'Google Sheets' : 'ملفات محلية'),
              ],
            ),
            const Text('·'),
            Text('${c.managementCount} / ${c.agentCount} سجل'),
            if (c.transferDiscountPct > 0) ...[
              const Text('·'),
              Text('خصم ${jsNumberToString(c.transferDiscountPct)}%'),
            ],
            _badge(state),
          ],
        ),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'إجراءات',
        icon: const Icon(Icons.more_vert, size: 20, color: Tw.slate500),
        onSelected: (v) {
          if (v == 'audit') widget.onAudit?.call(c.id);
          if (v == 'edit') _openModal(c);
          if (v == 'delete') _confirmDelete(c);
        },
        itemBuilder:
            (_) => const [
              PopupMenuItem(
                value: 'audit',
                height: 44,
                child: _MenuLine(Icons.fact_check_outlined, 'تدقيق الفترة'),
              ),
              PopupMenuItem(
                value: 'edit',
                height: 44,
                child: _MenuLine(Icons.edit_outlined, 'تعديل'),
              ),
              PopupMenuItem(
                value: 'delete',
                height: 44,
                child: _MenuLine(Icons.delete_outline, 'حذف', color: Tw.red600),
              ),
            ],
      ),
    );
  }
}

class _MenuLine extends StatelessWidget {
  const _MenuLine(this.icon, this.label, {this.color = Tw.slate900});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: color == Tw.slate900 ? Tw.slate500 : color),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 14, color: color)),
    ],
  );
}

// ======================================================================
// Create / edit modal
// ======================================================================

class CycleModal extends StatefulWidget {
  const CycleModal({super.key, this.edit});
  final Cycle? edit;
  @override
  State<CycleModal> createState() => _CycleModalState();
}

class _CycleModalState extends State<CycleModal> {
  bool _googleTab = true;
  bool _showSave = false;
  bool _busy = false;
  bool _saving = false;
  String? _listMessage = 'جاري التحميل...';
  List<SpreadsheetFile> _files = const [];
  String _mgmtSs = '';
  String _mgmtSheet = '';
  String _agentSs = '';
  String _agentSheet = '';
  List<String> _mgmtSheets = const [];
  List<String> _agentSheets = const [];
  ImportedFile? _mgmtFile;
  ImportedFile? _agentFile;
  Rows _currentMgmt = const [];
  Rows _currentAgent = const [];
  String _mgmtCount = '0';
  String _agentCount = '0';
  final _name = TextEditingController();
  final _discount = TextEditingController();

  AppServices get _s => AppScope.read(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _name.dispose();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadSpreadsheets();
    final e = widget.edit;
    if (e == null || !mounted) return;
    _name.text = e.name;
    _discount.text =
        e.transferDiscountPct == 0
            ? ''
            : jsNumberToString(e.transferDiscountPct);
    if (e.managementSpreadsheetId != null) {
      _mgmtSs = e.managementSpreadsheetId!;
      await _loadSheets(true, _mgmtSs);
      _mgmtSheet = e.managementSheetName ?? '';
    }
    if (e.agentSpreadsheetId != null) {
      _agentSs = e.agentSpreadsheetId!;
      await _loadSheets(false, _agentSs);
      _agentSheet = e.agentSheetName ?? '';
    }
    if (!mounted) return;
    setState(() {
      _showSave = true;
      _mgmtCount = '—';
      _agentCount = '—';
    });
  }

  Future<void> _loadSpreadsheets() async {
    setState(() => _listMessage = 'جاري التحميل...');
    try {
      final files = await _s.sheets.listSpreadsheets();
      if (!mounted) return;
      setState(() {
        _files = [
          ...files,
          for (final f in _files)
            if (!files.any((x) => x.id == f.id)) f,
        ];
        _listMessage = null;
      });
    } catch (e) {
      if (mounted) setState(() => _listMessage = e.toString());
    }
  }

  Future<void> _loadSheets(bool mgmt, String id) async {
    if (id.isEmpty) {
      setState(() => mgmt ? _mgmtSheets = const [] : _agentSheets = const []);
      return;
    }
    try {
      final meta = await _s.sheets.getSpreadsheet(id);
      if (!mounted) return;
      setState(() {
        final titles = [for (final s in meta.sheets) s.title];
        if (mgmt) {
          _mgmtSheets = titles;
        } else {
          _agentSheets = titles;
        }
      });
    } catch (_) {}
  }

  List<SelectOption<String>> _ssOptions() {
    final msg = _listMessage;
    if (msg != null) {
      return [
        SelectOption('', msg),
        const SelectOption(pasteLinkValue, pasteLinkLabel),
      ];
    }
    final known = {for (final f in _files) f.id};
    return [
      const SelectOption('', '— اختر الجدول —'),
      const SelectOption(pasteLinkValue, pasteLinkLabel),
      for (final f in _files) SelectOption(f.id, f.name),
      if (_mgmtSs.isNotEmpty && !known.contains(_mgmtSs))
        SelectOption(_mgmtSs, _mgmtSs),
      if (_agentSs.isNotEmpty &&
          !known.contains(_agentSs) &&
          _agentSs != _mgmtSs)
        SelectOption(_agentSs, _agentSs),
    ];
  }

  List<SelectOption<String>> _sheetOptions(
    List<String> titles,
    String current,
  ) => [
    const SelectOption('', 'أول ورقة تلقائياً'),
    for (final t in titles) SelectOption(t, t),
    if (current.isNotEmpty && !titles.contains(current))
      SelectOption(current, current),
  ];

  void _showSavePanel(Rows m, Rows a) {
    setState(() {
      _currentMgmt = m;
      _currentAgent = a;
      _mgmtCount = '${m.length}';
      _agentCount = '${a.length}';
      _showSave = true;
    });
  }

  Future<void> _primary() async {
    if (_googleTab) {
      await _fetchFromGoogle();
    } else {
      _uploadFiles();
    }
  }

  Future<void> _fetchFromGoogle() async {
    if (_mgmtSs.isEmpty || _agentSs.isEmpty) {
      showToast(
        context,
        'اختر جدول الإدارة وجدول الوكيل من القائمة',
        ToastType.error,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final (m, a) = await _s.cycles.importFromGoogle(
        managementSpreadsheetId: _mgmtSs,
        managementSheetName: _mgmtSheet,
        agentSpreadsheetId: _agentSs,
        agentSheetName: _agentSheet,
      );
      if (!mounted) return;
      _showSavePanel(m, a);
      showToast(context, 'تم جلب البيانات', ToastType.success);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool mgmt) async {
    try {
      final f = await pickSpreadsheetFile();
      if (f == null || !mounted) return;
      setState(() => mgmt ? _mgmtFile = f : _agentFile = f);
      final m = _mgmtFile;
      final a = _agentFile;
      if (_showSave && m != null && a != null) {
        _showSavePanel(m.firstSheetRows, a.firstSheetRows);
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString(), ToastType.error);
    }
  }

  void _uploadFiles() {
    final m = _mgmtFile;
    final a = _agentFile;
    if (m == null || a == null) {
      showToast(context, 'اختر ملف الإدارة وملف الوكيل', ToastType.error);
      return;
    }
    _showSavePanel(m.firstSheetRows, a.firstSheetRows);
    showToast(context, 'تم قراءة الملفات', ToastType.success);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, 'أدخل اسم الفترة', ToastType.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final tdpRaw = _discount.text.trim();
      final tdp = tdpRaw.isEmpty ? null : jsParseFloat(tdpRaw);
      var mSs = _mgmtSs.isEmpty ? null : _mgmtSs;
      var aSs = _agentSs.isEmpty ? null : _agentSs;
      Rows? mRows;
      Rows? aRows;
      final haveRows = _currentMgmt.isNotEmpty || _currentAgent.isNotEmpty;
      if ((mSs == null || aSs == null) && haveRows) {
        mRows = _currentMgmt;
        aRows = _currentAgent;
        mSs = null;
        aSs = null;
      } else if (mSs != null && aSs != null && _googleTab && haveRows) {
        mRows = _currentMgmt;
        aRows = _currentAgent;
      }
      final edit = widget.edit;
      if (edit == null) {
        await _s.cycles.createCycle(
          name: name,
          managementRows: mRows,
          agentRows: aRows,
          managementSpreadsheetId: mSs,
          managementSheetName: mSs == null ? null : _mgmtSheet,
          agentSpreadsheetId: aSs,
          agentSheetName: aSs == null ? null : _agentSheet,
          transferDiscountPct: tdp == null || tdp.isNaN ? 0 : tdp,
        );
      } else {
        await _s.cycles.updateCycle(
          edit.id,
          name: name,
          managementRows: mRows,
          agentRows: aRows,
          managementSpreadsheetId: mSs,
          managementSheetName: mSs == null ? null : _mgmtSheet,
          agentSpreadsheetId: aSs,
          agentSheetName: aSs == null ? null : _agentSheet,
          transferDiscountPct: tdp == null || tdp.isNaN ? null : tdp,
        );
      }
      if (!mounted) return;
      showToast(
        context,
        edit == null ? 'حُفظت فترة الرواتب' : 'حُدّثت فترة الرواتب',
        ToastType.success,
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_googleTab) ..._googlePanel() else ..._uploadPanel(),
                    if (_showSave) ...[
                      const SizedBox(height: 12),
                      _savePanel(),
                    ],
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    decoration: const BoxDecoration(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      border: Border(bottom: BorderSide(color: Tw.slate200)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
    child: Column(
      children: [
        const SheetHandle(),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.edit == null ? 'فترة رواتب جديدة' : 'تعديل فترة الرواتب',
                style: Ds.title,
              ),
            ),
            const InfoTip(
              'Google Sheets: اختر جدول وورقة الإدارة وجدول وورقة الوكيل من حسابك (أو الصق رابط الجدول)، ثم «جلب البيانات». الملفات: اختر ملفي Excel أو CSV للإدارة والوكيل. بعد القراءة اكتب اسم الفترة واحفظ.',
              title: 'فترة الرواتب',
            ),
            IconButton(
              tooltip: 'إغلاق',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 20, color: Tw.slate500),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.all(3),
          margin: const EdgeInsetsDirectional.only(end: 8),
          decoration: BoxDecoration(
            color: Tw.slate100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _tab('Google Sheets', Icons.cloud_outlined, _googleTab, () {
                setState(() => _googleTab = true);
                _loadSpreadsheets();
              }),
              _tab(
                'ملفات Excel / CSV',
                Icons.upload_file_outlined,
                !_googleTab,
                () => setState(() => _googleTab = false),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _tab(String label, IconData icon, bool active, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: active ? Border.all(color: Tw.slate200) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: active ? Tw.indigo600 : Tw.slate500,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? Tw.indigo700 : Tw.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  List<Widget> _googlePanel() => [
    _sourceBox(
      title: 'جدول الإدارة',
      icon: Icons.apartment_outlined,
      bg: const Color(0x66fffbeb),
      border: Tw.amber200,
      iconBg: Tw.amber100,
      iconFg: Tw.amber700,
      child: _ssPair(true),
    ),
    const SizedBox(height: 12),
    _sourceBox(
      title: 'جدول الوكيل',
      icon: Icons.badge_outlined,
      bg: const Color(0x80eef2ff),
      border: Tw.indigo200,
      iconBg: Tw.indigo100,
      iconFg: Tw.indigo700,
      child: _ssPair(false),
    ),
  ];

  Widget _ssPair(bool mgmt) {
    final ss = mgmt ? _mgmtSs : _agentSs;
    final sheet = mgmt ? _mgmtSheet : _agentSheet;
    final sheets = mgmt ? _mgmtSheets : _agentSheets;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('الجدول', small: true, bold: true),
              ErpSelect<String>(
                thick: true,
                options: _ssOptions(),
                value: ss,
                onChanged: (picked) async {
                  var v = picked;
                  if (v == pasteLinkValue) {
                    final f = await askSpreadsheetLink(context, _s.sheets);
                    if (f == null || !mounted) return;
                    setState(() {
                      _files = [f, ..._files.where((x) => x.id != f.id)];
                      _listMessage = null;
                    });
                    v = f.id;
                  }
                  setState(() {
                    if (mgmt) {
                      _mgmtSs = v;
                      _mgmtSheet = '';
                    } else {
                      _agentSs = v;
                      _agentSheet = '';
                    }
                  });
                  _loadSheets(mgmt, v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('الورقة', small: true, bold: true),
              ErpSelect<String>(
                thick: true,
                options: _sheetOptions(sheets, sheet),
                value: sheet,
                onChanged:
                    (v) =>
                        setState(() => mgmt ? _mgmtSheet = v : _agentSheet = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sourceBox({
    required String title,
    required IconData icon,
    required Color bg,
    required Color border,
    required Color iconBg,
    required Color iconFg,
    required Widget child,
  }) => Container(
    decoration: panelDecoration(),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconChip(icon, color: iconFg, bg: iconBg, size: 28),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Tw.slate900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  List<Widget> _uploadPanel() => [
    _sourceBox(
      title: 'ملف جدول الإدارة',
      icon: Icons.description_outlined,
      bg: const Color(0x66fffbeb),
      border: Tw.amber200,
      iconBg: Tw.amber100,
      iconFg: Tw.amber700,
      child: _filePicker(true),
    ),
    const SizedBox(height: 12),
    _sourceBox(
      title: 'ملف جدول الوكيل',
      icon: Icons.description_outlined,
      bg: const Color(0x80eef2ff),
      border: Tw.indigo200,
      iconBg: Tw.indigo100,
      iconFg: Tw.indigo700,
      child: _filePicker(false),
    ),
  ];

  Widget _filePicker(bool mgmt) {
    final f = mgmt ? _mgmtFile : _agentFile;
    return InkWell(
      onTap: () => _pick(mgmt),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tw.slate200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: mgmt ? Tw.amber100 : Tw.indigo100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'اختيار ملف',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: mgmt ? Tw.amber900 : Tw.indigo900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                f == null
                    ? 'لم يتم اختيار ملف (.xlsx, .csv)'
                    : '${f.fileName} — ${f.firstSheetRows.length} صف',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Tw.slate600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _savePanel() => Container(
    padding: const EdgeInsets.all(12),
    decoration: panelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _countTile('سجلات الإدارة', _mgmtCount)),
            const SizedBox(width: 8),
            Expanded(child: _countTile('سجلات الوكيل', _agentCount)),
          ],
        ),
        const SizedBox(height: 12),
        const FieldHeader('اسم الفترة'),
        ErpTextField(controller: _name, hint: 'مثال: رواتب يناير 2026'),
        const SizedBox(height: 10),
        const FieldHeader(
          'نسبة خصم التحويل (%)',
          info:
              'تُحفظ مع الفترة كما في النظام. خصم التدقيق نفسه يُحدَّد من شاشة التدقيق ← إعداد التدقيق.',
        ),
        ErpTextField(
          controller: _discount,
          hint: '0',
          ltr: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    ),
  );

  Widget _countTile(String label, String count) =>
      StatTile(label: label, value: count, color: Tw.indigo600);

  Widget _footer() => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Tw.slate100)),
    ),
    padding: EdgeInsets.fromLTRB(
      12,
      10,
      12,
      10 + MediaQuery.of(context).padding.bottom,
    ),
    child:
        !_showSave
            ? ErpButton(
              label: _googleTab ? 'جلب البيانات' : 'تحميل الملفات',
              loadingLabel: _googleTab ? 'جاري الجلب...' : 'جاري القراءة...',
              icon:
                  _googleTab
                      ? Icons.cloud_download_outlined
                      : Icons.upload_file_outlined,
              kind: ErpButtonKind.indigo,
              loading: _busy,
              onPressed: _primary,
            )
            : Row(
              children: [
                Expanded(
                  child: ErpButton(
                    label: 'إلغاء',
                    kind: ErpButtonKind.soft,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ErpButton(
                    label: 'حفظ',
                    loadingLabel: 'جاري الحفظ...',
                    icon: Icons.save_outlined,
                    loading: _saving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
  );
}
