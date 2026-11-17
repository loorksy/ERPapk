// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_services.dart';
import '../data/app_database.dart';
import '../erp/normalize.dart';
import '../google/sheets_client.dart';
import '../services/adjustments_service.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'spreadsheet_link.dart';
import 'ui_kit.dart';

const _draftKey = 'adjustmentsDraftV1';

/// ERP «إضافات وخصومات» (`views/partials/member-adjustments.ejs`), bulk
/// only and without the advanced accounting registration (owner's
/// decision, 2026-11-17). Separate from the audit.
class AdjustmentsPage extends StatefulWidget {
  const AdjustmentsPage({super.key, required this.active});
  final bool active;

  @override
  State<AdjustmentsPage> createState() => _AdjustmentsPageState();
}

class _AdjustmentsPageState extends State<AdjustmentsPage> {
  bool _ready = false;
  String? _ssMessage = 'جاري جلب الملفات…';
  List<SpreadsheetFile> _files = const [];
  String _ssId = '';
  List<String> _sheetNames = const [];
  String? _sheetMessage = 'اختر الجدول أولاً';
  String _sheet = '';
  String _idCol = AdjustmentsService.defaultIdCol;
  String _salaryCol = AdjustmentsService.defaultSalaryCol;
  String _statusCol = AdjustmentsService.defaultStatusCol;
  final _bulk = TextEditingController();

  AuditJob? _job;
  Timer? _poll;
  AdjustOutcome? _last;
  int? _lastJobId;
  String _lastSsId = '';

  /// ERP offers columns A–Z.
  static final _letters = [for (var i = 0; i < 26; i++) columnIndexToLetter(i)];

  AppServices get _s => AppScope.read(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    _init();
  }

  @override
  void didUpdateWidget(AdjustmentsPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && _files.isEmpty) _loadFiles();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _bulk.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _restoreDraft();
    await _loadFiles();
    await _watchJob();
  }

  // --------------------------------------------------------------- draft

  Future<void> _saveDraft() => _s.db.setValue(
    _draftKey,
    jsonEncode({
      'ssId': _ssId,
      'sheet': _sheet,
      'idCol': _idCol,
      'salaryCol': _salaryCol,
      'statusCol': _statusCol,
      'bulk': _bulk.text,
    }),
  );

  Future<void> _restoreDraft() async {
    final raw = await _s.db.getValue(_draftKey);
    if (raw == null || !mounted) return;
    try {
      final d = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      String col(String key, String fallback) {
        final v = d[key]?.toString() ?? '';
        return _letters.contains(v) ? v : fallback;
      }

      setState(() {
        _ssId = d['ssId']?.toString() ?? '';
        _sheet = d['sheet']?.toString() ?? '';
        _idCol = col('idCol', _idCol);
        _salaryCol = col('salaryCol', _salaryCol);
        _statusCol = col('statusCol', _statusCol);
        _bulk.text = d['bulk']?.toString() ?? '';
      });
      if (_ssId.isNotEmpty) await _loadSheets(keep: true);
    } catch (_) {}
  }

  // -------------------------------------------------------------- google

  Future<void> _loadFiles() async {
    setState(() => _ssMessage = 'جاري جلب الملفات…');
    try {
      final list = await _s.sheets.listSpreadsheets();
      if (!mounted) return;
      setState(() {
        _files = list;
        _ssMessage = list.isEmpty ? 'لا توجد ملفات — تحقق من ربط Google' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _ssMessage = '$e');
    }
  }

  Future<void> _onSpreadsheet(String picked) async {
    var v = picked;
    if (v == pasteLinkValue) {
      final f = await askSpreadsheetLink(context, _s.sheets);
      if (f == null || !mounted) return;
      setState(() {
        _files = [f, ..._files.where((x) => x.id != f.id)];
        _ssMessage = null;
      });
      v = f.id;
    }
    setState(() {
      _ssId = v;
      _sheet = '';
      _sheetNames = const [];
    });
    await _loadSheets();
    _saveDraft();
  }

  Future<void> _loadSheets({bool keep = false}) async {
    if (_ssId.isEmpty) {
      setState(() => _sheetMessage = 'اختر الجدول أولاً');
      return;
    }
    setState(() => _sheetMessage = 'جاري جلب الأوراق…');
    try {
      final meta = await _s.sheets.getSpreadsheet(_ssId);
      if (!mounted) return;
      final names = [for (final s in meta.sheets) s.title];
      setState(() {
        _sheetNames = names;
        _sheetMessage = names.isEmpty ? 'لا توجد أوراق' : null;
        if (!keep || !names.contains(_sheet)) {
          _sheet = names.isEmpty ? '' : names.first;
        }
        if (!_files.any((f) => f.id == _ssId)) {
          _files = [SpreadsheetFile(_ssId, meta.title ?? _ssId), ..._files];
        }
      });
    } catch (e) {
      if (mounted) setState(() => _sheetMessage = '$e');
    }
  }

  // ----------------------------------------------------------------- run

  Future<void> _run() async {
    if (_ssId.isEmpty || _sheet.isEmpty || _bulk.text.trim().isEmpty) {
      showToast(context, 'الرجاء إكمال البيانات', ToastType.error);
      return;
    }
    if (_job?.active ?? false) {
      showToast(
        context,
        'توجد معالجة قيد التنفيذ. انتظر انتهاءها.',
        ToastType.warning,
      );
      return;
    }
    await _saveDraft();
    await _s.startAdjustments(
      AdjustRequest(
        spreadsheetId: _ssId,
        sheetName: _sheet,
        idCol: _idCol,
        salaryCol: _salaryCol,
        statusCol: _statusCol,
        bulkData: _bulk.text,
      ),
    );
    await _watchJob();
  }

  Future<void> _watchJob() async {
    _poll?.cancel();
    final job = await _s.db.latestCyclelessJob();
    if (!mounted) return;
    setState(() => _job = job);
    if (job == null) return;
    if (job.active) {
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _pollJob());
    } else {
      await _settle(job);
    }
  }

  Future<void> _pollJob() async {
    final current = _job;
    if (current == null) return;
    final job = await _s.db.getAuditJob(current.id);
    if (!mounted || job == null) return;
    setState(() => _job = job);
    if (!job.active) {
      _poll?.cancel();
      await _settle(job);
    } else if (job.status == AuditJob.queued &&
        DateTime.now().difference(job.updatedAt).inSeconds > 20) {
      await _s.resumeAuditJobs();
    }
  }

  /// A finished job: ERP opens the results window; here once per job.
  Future<void> _settle(AuditJob job) async {
    final json = await _s.db.getAuditJobResult(job.id);
    if (!mounted) return;
    final out = json == null ? null : AdjustOutcome.fromJson(json);
    if (out != null && out.success) {
      setState(() {
        _last = out;
        _lastJobId = job.id;
        _lastSsId = (job.request['spreadsheetId'] ?? '').toString();
      });
    }
    if (job.seen) return;
    await _s.db.updateAuditJob(job.id, {'seen': 1});
    if (!mounted) return;
    if (out == null || !out.success) {
      showToast(context, out?.message ?? job.error ?? 'فشل', ToastType.error);
      return;
    }
    // The list was applied: clear it so it is not sent twice.
    _bulk.clear();
    _saveDraft();
    await _showResults(out);
  }

  Future<void> _showResults(AdjustOutcome out) => showDialog<void>(
    context: context,
    builder:
        (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: _ResultsDialog(
            out,
            jobId: _lastJobId,
            spreadsheetId: _lastSsId,
            onChanged: (o) {
              if (mounted) setState(() => _last = o);
            },
          ),
        ),
  );

  // ------------------------------------------------------------------ UI
  //
  // Owner's redesign (2026-11-17): panels without a page heading, details
  // behind «!», the columns folded by default. Same controls and actions.

  Widget _select(
    String label,
    List<SelectOption<String>> options,
    String value,
    ValueChanged<String> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldHeader(label),
      ErpSelect<String>(options: options, value: value, onChanged: onChanged),
    ],
  );

  List<SelectOption<String>> get _letterOptions => [
    for (final l in _letters) SelectOption(l, l),
  ];

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final busy = job?.active ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Panel(
          title: 'جدول البيانات',
          icon: FontAwesomeIcons.table,
          iconColor: Tw.emerald600,
          iconBg: Tw.emerald50,
          info:
              'الجدول والورقة التي فيها رواتب المستخدمين (عادة جدول معلومات المستخدمين). تُعدَّل فيها الرواتب ويُكتب عمود الحالة، ومنها تُنشأ ورقة «إضافات وخصومات» عند «دفع إلى الشيت».',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _select(
                'الجدول',
                [
                  SelectOption('', _ssMessage ?? '— اختر جدول البيانات —'),
                  const SelectOption(pasteLinkValue, pasteLinkLabel),
                  for (final f in _files) SelectOption(f.id, f.name),
                  if (_ssId.isNotEmpty && !_files.any((f) => f.id == _ssId))
                    SelectOption(_ssId, _ssId),
                ],
                _ssId,
                _onSpreadsheet,
              ),
              const SizedBox(height: 10),
              _select(
                'الورقة',
                [
                  if (_sheetNames.isEmpty)
                    SelectOption('', _sheetMessage ?? 'لا توجد أوراق'),
                  for (final n in _sheetNames) SelectOption(n, n),
                  if (_sheet.isNotEmpty && !_sheetNames.contains(_sheet))
                    SelectOption(_sheet, _sheet),
                ],
                _sheet,
                (v) {
                  setState(() => _sheet = v);
                  _saveDraft();
                },
              ),
            ],
          ),
        ),
        gap,
        CollapsiblePanel(
          title: 'الأعمدة',
          icon: FontAwesomeIcons.tableColumns,
          info:
              'عمود رقم المستخدم، وعمود الراتب الذي يُعدَّل، وعمود الحالة الذي يُكتب فيه «تم خصم …» أو «تم اضافة …». الافتراضي كما في النظام: C و L و O.',
          summary: SummaryText(
            'ID $_idCol · الراتب $_salaryCol · الحالة $_statusCol',
          ),
          child: Row(
            children: [
              for (final (i, label, value, set) in [
                (0, 'عمود ID', _idCol, (String v) => _idCol = v),
                (1, 'عمود الراتب', _salaryCol, (String v) => _salaryCol = v),
                (2, 'عمود الحالة', _statusCol, (String v) => _statusCol = v),
              ]) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _select(label, _letterOptions, value, (v) {
                    setState(() => set(v));
                    _saveDraft();
                  }),
                ),
              ],
            ],
          ),
        ),
        gap,
        Panel(
          title: 'القائمة',
          icon: FontAwesomeIcons.listOl,
          iconColor: Tw.violet500,
          iconBg: const Color(0xfff5f3ff),
          info:
              'كل سطر: رقم المستخدم ← النوع ← المبلغ، مفصولة بـTab (كما تُنسخ من Excel) أو بمسافات. النوع «خصم» يخصم، وأي نوع آخر (اضافة، إضافة…) يضيف. للخصم الكامل: «12345  خصم كامل» بدون مبلغ.\n\nإذا جاء نفس الرقم بإضافة وخصم في القائمة نفسها تُجمع عملياته أولًا في تسوية واحدة (الإضافات ناقص الخصومات) ثم تُطبَّق مرة واحدة، ويُكتب في عمود الحالة «تم خصم …» أو «تم اضافة …» مع تفاصيل التسوية.\n\nتكمل المعالجة في الخلفية، وإذا انقطع الإنترنت تُستأنف دون تكرار أي إضافة أو خصم.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _bulk,
                minLines: 6,
                maxLines: 14,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => _saveDraft(),
                style: const TextStyle(fontSize: 14, height: 1.5),
                decoration: InputDecoration(
                  hintText: '12345\tخصم\t50',
                  hintTextDirection: TextDirection.ltr,
                  isDense: true,
                  filled: true,
                  fillColor: Tw.slate50,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Tw.slate200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Tw.slate200),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ErpButton(
                label: 'معالجة القائمة',
                icon: FontAwesomeIcons.play,
                kind: ErpButtonKind.slate,
                loading: busy,
                loadingLabel: 'جاري المعالجة…',
                onPressed: _run,
              ),
              if (job != null && job.active) ...[
                const SizedBox(height: 10),
                _jobBox(job),
              ],
              if (_last != null && !busy) ...[
                const SizedBox(height: 8),
                ErpButton(
                  label: 'عرض نتائج آخر معالجة',
                  icon: FontAwesomeIcons.clipboardList,
                  kind: ErpButtonKind.outline,
                  height: 42,
                  fontSize: 12.5,
                  onPressed: () => _showResults(_last!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _jobBox(AuditJob job) {
    final waiting = job.status == AuditJob.waiting;
    return NoticeBox(
      bg: waiting ? Tw.amber50 : Tw.sky50,
      border: waiting ? Tw.amber200 : Tw.sky200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  waiting
                      ? 'المعالجة متوقفة مؤقتًا — بانتظار الاتصال'
                      : 'جاري المعالجة… يتم تحديث جدول البيانات',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: waiting ? Tw.amber900 : Tw.sky800,
                  ),
                ),
              ),
              const InfoTip(
                'يمكنك إغلاق التطبيق: تكمل المعالجة في الخلفية، وإذا انقطع الإنترنت تُستأنف دون تكرار أي إضافة أو خصم.',
                title: 'العمل في الخلفية',
              ),
            ],
          ),
          Text(
            job.progress ?? '',
            style: const TextStyle(fontSize: 12, color: Tw.slate600),
          ),
          if (waiting) ...[
            const SizedBox(height: 8),
            ErpButton(
              label: 'استئناف الآن',
              icon: FontAwesomeIcons.play,
              kind: ErpButtonKind.amber,
              height: 38,
              fontSize: 12.5,
              onPressed: () => _s.resumeAuditJobs(now: true),
            ),
          ],
        ],
      ),
    );
  }
}

/// ERP «نتائج المعالجة»: totals, debtors, the table and «نسخ»; plus the
/// owner's «دفع إلى الشيت».
class _ResultsDialog extends StatefulWidget {
  const _ResultsDialog(
    this.out, {
    required this.jobId,
    required this.spreadsheetId,
    required this.onChanged,
  });
  final AdjustOutcome out;
  final int? jobId;
  final String spreadsheetId;
  final ValueChanged<AdjustOutcome> onChanged;

  @override
  State<_ResultsDialog> createState() => _ResultsDialogState();
}

class _ResultsDialogState extends State<_ResultsDialog> {
  late AdjustOutcome out = widget.out;
  bool _pushing = false;

  /// Owner's request: the pasted lines, the results, the totals and the
  /// settled users in a new sheet «إضافات وخصومات» of the same spreadsheet.
  Future<void> _push() async {
    final services = AppScope.read(context);
    final jobId = widget.jobId;
    if (jobId == null || widget.spreadsheetId.isEmpty) return;
    setState(() => _pushing = true);
    try {
      final done = await services.adjustments.pushResults(
        widget.spreadsheetId,
        out,
        (o) => services.db.updateAuditJob(jobId, {
          'result_json': jsonEncode(o.toJson()),
        }),
      );
      if (!mounted) return;
      setState(() => out = done);
      widget.onChanged(done);
      showToast(
        context,
        'تمت الكتابة في ورقة «${done.pushedSheet}»',
        ToastType.success,
      );
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          'تعذّر الدفع إلى الشيت: $e — أعد المحاولة (لن تُنشأ ورقة ثانية).',
          ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  void _open() {
    final base = out.spreadsheetUrl;
    if (base == null) return;
    launchUrl(
      Uri.parse('$base#gid=${out.pushedSheetId ?? 0}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = out.summary ?? AdjustmentsService.summarize(out.results);
    Widget tile(String label, double v, Color bg, Color border, Color fg) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AdjustmentsService.money(v),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        );
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.clipboardList,
                    size: 14,
                    color: Tw.sky600,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'نتائج المعالجة',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Tw.slate900,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Tw.sky700,
                      side: const BorderSide(color: Tw.sky300),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: AdjustmentsService.copyText(out.results, s),
                        ),
                      );
                      if (context.mounted) {
                        showToast(
                          context,
                          'تم نسخ الجدول والملخص بنجاح! الصقه الآن في الإكسل.',
                          ToastType.success,
                        );
                      }
                    },
                    icon: const FaIcon(FontAwesomeIcons.copy, size: 12),
                    label: const Text(
                      'نسخ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const FaIcon(
                      FontAwesomeIcons.xmark,
                      size: 16,
                      color: Tw.slate500,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Tw.slate100),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      tile(
                        'إضافة',
                        s.totalAdded,
                        Tw.emerald50,
                        Tw.emerald200,
                        Tw.emerald800,
                      ),
                      const SizedBox(width: 8),
                      tile(
                        'خصم فعلي',
                        s.totalDeducted,
                        Tw.sky50,
                        Tw.sky200,
                        Tw.sky800,
                      ),
                      const SizedBox(width: 8),
                      tile(
                        'المتبقي',
                        s.totalDebt,
                        Tw.amber50,
                        Tw.amber200,
                        Tw.amber800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  out.pushed
                      ? ErpButton(
                        label: 'فتح ورقة «${out.pushedSheet}»',
                        icon: FontAwesomeIcons.arrowUpRightFromSquare,
                        kind: ErpButtonKind.outline,
                        height: 38,
                        fontSize: 12.5,
                        onPressed: _open,
                      )
                      : ErpButton(
                        label: 'دفع إلى الشيت (ورقة «إضافات وخصومات»)',
                        icon: FontAwesomeIcons.fileExport,
                        kind: ErpButtonKind.indigoSoft,
                        height: 38,
                        fontSize: 12.5,
                        loading: _pushing,
                        loadingLabel: 'جاري الكتابة في الشيت…',
                        onPressed: widget.jobId == null ? null : _push,
                      ),
                  if (s.debtUsers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Tw.amber50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Tw.amber300),
                      ),
                      child: Text(
                        'الديون على: ${s.debtUsers.join(' ، ')}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Tw.amber900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              color: Tw.slate100,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Row(
                children: [
                  Expanded(child: _Head('رقم المستخدم')),
                  Expanded(child: _Head('الحالة')),
                  Expanded(child: _Head('المبلغ')),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: out.results.length,
                separatorBuilder:
                    (_, _) => const Divider(height: 1, color: Tw.slate100),
                itemBuilder: (_, i) => _ResultRow(out.results[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Tw.slate500,
    ),
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.r);
  final AdjustResult r;

  @override
  Widget build(BuildContext context) {
    final st = r.status;
    // ERP badge colours.
    final (bg, fg, border) =
        st.contains('باقي')
            ? (Tw.amber100, Tw.amber800, Tw.amber200)
            : st.contains('غير موجود') ||
                st.contains('سحب ادارة') ||
                st.contains('خطأ')
            ? (Tw.red100, Tw.red700, Tw.red200)
            : (Tw.emerald100, Tw.emerald800, Tw.emerald200);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              r.id,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Tw.slate800),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    st,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
                if (r.settlement != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'تسوية: ${r.settlement}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: Tw.slate500),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              AdjustmentsService.money(r.amount),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Tw.slate800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
