// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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

/// ERP «Sheet» page: the list of financial cycles and the create/edit modal.
class SheetPage extends StatefulWidget {
  const SheetPage({super.key});
  @override
  State<SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<SheetPage> {
  List<Cycle>? _cycles;
  int _revision = -1;

  static const _gradients = [
    [Tw.indigo500, Tw.violet500],
    [Tw.emerald500, Tw.teal500],
    [Tw.amber500, Tw.orange500],
    [Tw.rose500, Tw.pink500],
    [Tw.purple500, Tw.indigo500],
  ];

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
    final list = await AppScope.read(context).db.listCycles();
    if (mounted) setState(() => _cycles = list);
  }

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
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Tw.red100,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const FaIcon(
                        FontAwesomeIcons.trashCan,
                        color: Tw.red600,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'حذف الدورة المالية',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Tw.slate900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'هل أنت متأكد من حذف "${c.name}"؟ لا يمكن التراجع عن هذا الإجراء. لا يُحذف أي شيء من Google.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Tw.slate600),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ErpButton(
                            label: 'إلغاء',
                            kind: ErpButtonKind.soft,
                            onPressed: () => Navigator.pop(ctx, false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ErpButton(
                            label: 'حذف نهائياً',
                            icon: FontAwesomeIcons.trashCan,
                            kind: ErpButtonKind.danger,
                            onPressed: () => Navigator.pop(ctx, true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
    if (ok != true || !mounted) return;
    await AppScope.read(context).cycles.deleteCycle(c.id);
    if (!mounted) return;
    showToast(context, 'تم حذف الدورة', ToastType.success);
    AppScope.read(context).cyclesChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cycles = _cycles;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          ActionWithInfo(
            title: 'الدورات المالية',
            info:
                'الدورة المالية تجمع جدول الإدارة وجدول الوكيل (من Google Sheets أو من ملفات Excel / CSV). اختر الدورة في «تدقيق راتب» لتدقيق الرواتب عليها. اسحب للأسفل للتحديث.',
            button: ErpButton(
              label: 'إنشاء دورة جديدة',
              icon: FontAwesomeIcons.plus,
              onPressed: () => _openModal(),
            ),
          ),
          gap,
          if (cycles == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (cycles.isEmpty)
            Container(
              decoration: panelDecoration(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 56,
                  horizontal: 24,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Tw.indigo50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const FaIcon(
                        FontAwesomeIcons.fileExcel,
                        color: Tw.indigo500,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'لا توجد دورات محفوظة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Tw.slate800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'أنشئ دورة مالية جديدة لربط جداول الإدارة والوكيل',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Tw.slate500),
                    ),
                    const SizedBox(height: 24),
                    ErpButton(
                      label: 'إنشاء أول دورة',
                      icon: FontAwesomeIcons.plus,
                      expand: false,
                      onPressed: () => _openModal(),
                    ),
                  ],
                ),
              ),
            )
          else
            for (var i = 0; i < cycles.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _card(cycles[i], i),
              ),
        ],
      ),
    );
  }

  Widget _card(Cycle c, int i) {
    final g = _gradients[i % _gradients.length];
    return Container(
      decoration: panelDecoration(),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(colors: g),
                ),
                alignment: Alignment.center,
                child: const FaIcon(
                  FontAwesomeIcons.fileExcel,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name.isEmpty ? 'دورة' : c.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Tw.slate900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatArabicDate(c.createdAt),
                      style: const TextStyle(fontSize: 12, color: Tw.slate500),
                    ),
                  ],
                ),
              ),
              _iconBtn(
                FontAwesomeIcons.penToSquare,
                Tw.indigo600,
                Tw.indigo50,
                () => _openModal(c),
                'تعديل',
              ),
              _iconBtn(
                FontAwesomeIcons.trashCan,
                Tw.red600,
                Tw.red50,
                () => _confirmDelete(c),
                'حذف',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              c.linkedToGoogle ? ErpBadge.google() : ErpBadge.local(),
              if (c.auditClosedAt != null)
                const Pill('التدقيق مغلق', icon: FontAwesomeIcons.lock),
              if (c.transferDiscountPct > 0)
                Pill(
                  'خصم التحويل ${jsNumberToString(c.transferDiscountPct)}%',
                  icon: FontAwesomeIcons.percent,
                  bg: Tw.indigo50,
                  fg: Tw.indigo800,
                ),
              Pill(
                'الإدارة ${c.managementCount} · الوكيل ${c.agentCount} صف',
                icon: FontAwesomeIcons.layerGroup,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(
    FaIconData icon,
    Color fg,
    Color bg,
    VoidCallback onTap,
    String tip,
  ) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: FaIcon(icon, size: 14, color: fg),
      ),
    ),
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
      showToast(context, 'أدخل اسم الدورة', ToastType.error);
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
        edit == null ? 'تم حفظ الدورة المالية' : 'تم تحديث الدورة',
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      border: Border(bottom: BorderSide(color: Tw.slate100)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Tw.slate200),
                  ),
                  alignment: Alignment.center,
                  child: const FaIcon(
                    FontAwesomeIcons.xmark,
                    color: Tw.slate600,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Tw.indigo100,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const FaIcon(
                  FontAwesomeIcons.fileExcel,
                  color: Tw.indigo600,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.edit == null ? 'إنشاء دورة مالية' : 'تعديل الدورة',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Tw.slate900,
                  ),
                ),
              ),
              const InfoTip(
                'Google Sheets: اختر جدول وورقة الإدارة وجدول وورقة الوكيل من حسابك (أو الصق رابط الجدول)، ثم «جلب البيانات». رفع ملفات: اختر ملفي Excel أو CSV للإدارة والوكيل. بعد القراءة اكتب اسم الدورة واحفظ.',
                title: 'إنشاء دورة مالية',
              ),
            ],
          ),
        ),
        Container(
          color: const Color(0xccf8fafc),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              _tab('Google Sheets', FontAwesomeIcons.cloud, _googleTab, () {
                setState(() => _googleTab = true);
                _loadSpreadsheets();
              }),
              const SizedBox(width: 6),
              _tab(
                'رفع ملفات',
                FontAwesomeIcons.upload,
                !_googleTab,
                () => setState(() => _googleTab = false),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _tab(
    String label,
    FaIconData icon,
    bool active,
    VoidCallback onTap,
  ) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active ? Border.all(color: Tw.slate200) : null,
          boxShadow:
              active
                  ? const [BoxShadow(color: Color(0x0f0f172a), blurRadius: 2)]
                  : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(icon, size: 13, color: active ? Tw.indigo600 : Tw.slate600),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Tw.indigo600 : Tw.slate600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _googlePanel() => [
    _sourceBox(
      title: 'الإدارة',
      icon: FontAwesomeIcons.building,
      bg: const Color(0x66fffbeb),
      border: Tw.amber200,
      iconBg: Tw.amber100,
      iconFg: Tw.amber700,
      child: _ssPair(true),
    ),
    const SizedBox(height: 12),
    _sourceBox(
      title: 'الوكيل',
      icon: FontAwesomeIcons.userTie,
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
    required FaIconData icon,
    required Color bg,
    required Color border,
    required Color iconBg,
    required Color iconFg,
    required Widget child,
  }) => NoticeBox(
    bg: bg,
    border: border,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: FaIcon(icon, size: 11, color: iconFg),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Tw.slate800,
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
      title: 'ملف الإدارة',
      icon: FontAwesomeIcons.file,
      bg: const Color(0x66fffbeb),
      border: Tw.amber200,
      iconBg: Tw.amber100,
      iconFg: Tw.amber700,
      child: _filePicker(true),
    ),
    const SizedBox(height: 12),
    _sourceBox(
      title: 'ملف الوكيل',
      icon: FontAwesomeIcons.file,
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
          border: Border.all(color: Tw.slate200, width: 2),
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
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Tw.slate200),
      gradient: const LinearGradient(colors: [Tw.slate50, Colors.white]),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _countTile('الإدارة', _mgmtCount)),
            const SizedBox(width: 10),
            Expanded(child: _countTile('الوكيل', _agentCount)),
          ],
        ),
        const SizedBox(height: 12),
        const FieldLabel('اسم الدورة المالية', small: true, bold: true),
        ErpTextField(
          controller: _name,
          hint: 'مثال: دورة يناير 2025',
          thick: true,
        ),
        const SizedBox(height: 12),
        const FieldHeader(
          'نسبة الخصم (%)',
          info:
              'تُحفظ مع الدورة كما في النظام. خصم التدقيق نفسه يُحدَّد من صفحة تدقيق الرواتب.',
        ),
        ErpTextField(
          controller: _discount,
          hint: '0',
          thick: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    ),
  );

  Widget _countTile(String label, String count) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Tw.slate200),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Tw.slate500,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          count,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Tw.indigo600,
          ),
        ),
        const Text(
          'صف',
          style: TextStyle(
            fontSize: 12,
            color: Tw.slate500,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

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
                      ? FontAwesomeIcons.cloudArrowDown
                      : FontAwesomeIcons.upload,
              kind: ErpButtonKind.emerald,
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
                    icon: FontAwesomeIcons.floppyDisk,
                    loading: _saving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
  );
}
