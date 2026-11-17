// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      showToast(context, 'اختر الجدول والورقة وأدخل القائمة', ToastType.error);
      return;
    }
    if (_job?.active ?? false) {
      showToast(
        context,
        'يوجد تطبيق تسويات قيد التنفيذ. انتظر انتهاءه.',
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

  Future<void> _showResults(AdjustOutcome out) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
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
  // «Compact Fluid UI» (3.0): an editor — where the salaries are, the list
  // with live counts, one primary action — and the last results as a
  // summary that opens the full report in a bottom sheet.

  bool _mappingOpen = false;

  List<SelectOption<String>> get _letterOptions => [
    for (final l in _letters) SelectOption(l, l),
  ];

  Future<void> _paste() async {
    final t = await pasteText();
    if (t == null || t.isEmpty || !mounted) return;
    setState(() => _bulk.text = t);
    _saveDraft();
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final busy = job?.active ?? false;
    final lines = AdjustmentsService.parseLines(_bulk.text);
    final adds = lines.where((l) => !l.full && !l.isDeduction).length;
    final deds = lines.where((l) => l.isDeduction).length;
    final full = lines.where((l) => l.full).length;
    final byId = <String, Set<bool>>{};
    for (final l in lines.where((l) => !l.full)) {
      byId.putIfAbsent(l.userId, () => {}).add(l.isDeduction);
    }
    final netted = byId.values.where((s) => s.length == 2).length;
    return ListView(
      padding: Ds.pagePadding,
      children: [
        const SectionLabel(
          'جدول الرواتب',
          trailing: InfoTip(
            'الجدول والورقة التي فيها رواتب المستخدمين (عادة بيانات المستخدمين). يُعدَّل فيها عمود الراتب ويُكتب عمود الحالة، ومنها تُنشأ ورقة «إضافات وخصومات» عند التصدير.',
            title: 'جدول الرواتب',
          ),
        ),
        Container(
          decoration: panelDecoration(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ErpSelect<String>(
                options: [
                  SelectOption('', _ssMessage ?? '— اختر جدول البيانات —'),
                  const SelectOption(pasteLinkValue, pasteLinkLabel),
                  for (final f in _files) SelectOption(f.id, f.name),
                  if (_ssId.isNotEmpty && !_files.any((f) => f.id == _ssId))
                    SelectOption(_ssId, _ssId),
                ],
                value: _ssId,
                onChanged: _onSpreadsheet,
              ),
              const SizedBox(height: 8),
              ErpSelect<String>(
                muted: true,
                options: [
                  if (_sheetNames.isEmpty)
                    SelectOption('', _sheetMessage ?? 'لا توجد أوراق'),
                  for (final n in _sheetNames) SelectOption(n, n),
                  if (_sheet.isNotEmpty && !_sheetNames.contains(_sheet))
                    SelectOption(_sheet, _sheet),
                ],
                value: _sheet,
                onChanged: (v) {
                  setState(() => _sheet = v);
                  _saveDraft();
                },
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _mappingOpen = !_mappingOpen),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.view_column_outlined,
                        size: 18,
                        color: Tw.slate500,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'ربط الحقول',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Tw.slate700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SummaryText(
                          'المعرّف $_idCol · الراتب $_salaryCol · الحالة $_statusCol',
                        ),
                      ),
                      AnimatedRotation(
                        turns: _mappingOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.expand_more,
                          size: 20,
                          color: Tw.slate400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_mappingOpen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      for (final (i, label, value, set) in [
                        (0, 'المعرّف', _idCol, (String v) => _idCol = v),
                        (1, 'الراتب', _salaryCol, (String v) => _salaryCol = v),
                        (2, 'الحالة', _statusCol, (String v) => _statusCol = v),
                      ]) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FieldHeader(label),
                              ErpSelect<String>(
                                muted: true,
                                options: _letterOptions,
                                value: value,
                                onChanged: (v) {
                                  setState(() => set(v));
                                  _saveDraft();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionLabel(
          'قائمة التسويات',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'لصق',
                visualDensity: VisualDensity.compact,
                onPressed: _paste,
                icon: const Icon(
                  Icons.content_paste_outlined,
                  size: 18,
                  color: Tw.slate500,
                ),
              ),
              if (_bulk.text.isNotEmpty)
                IconButton(
                  tooltip: 'مسح القائمة',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(_bulk.clear);
                    _saveDraft();
                  },
                  icon: const Icon(
                    Icons.backspace_outlined,
                    size: 18,
                    color: Tw.slate500,
                  ),
                ),
              const InfoTip(
                'كل سطر: رقم المستخدم ← النوع ← المبلغ، مفصولة بـTab (كما تُنسخ من Excel) أو بمسافات. النوع «خصم» يخصم، وأي نوع آخر (اضافة، إضافة…) يضيف. للخصم الكامل: «12345  خصم كامل» بدون مبلغ.\n\nالمقاصة: إذا جاء نفس الرقم بإضافة وخصم في القائمة نفسها تُجمع عملياته أولًا (الإضافات ناقص الخصومات) وتُطبَّق مرة واحدة، ويُكتب في عمود الحالة «تم خصم …» أو «تم اضافة …» مع تفاصيل المقاصة.\n\nيعمل التطبيق في الخلفية، وإذا انقطع الإنترنت يُستأنف دون تكرار أي إضافة أو خصم.',
                title: 'قائمة التسويات',
              ),
            ],
          ),
        ),
        Container(
          decoration: panelDecoration(),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _bulk,
                minLines: 6,
                maxLines: 14,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.multiline,
                onChanged: (_) {
                  setState(() {});
                  _saveDraft();
                },
                style: const TextStyle(fontSize: 14, height: 1.5),
                decoration: const InputDecoration(
                  hintText: '12345\tخصم\t50',
                  hintTextDirection: TextDirection.ltr,
                  fillColor: Tw.slate50,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusBadge('${lines.length} سطر'),
                  StatusBadge('إضافة $adds', tone: Tone.success),
                  StatusBadge('خصم $deds', tone: Tone.warning),
                  if (full > 0)
                    StatusBadge('خصم كامل $full', tone: Tone.danger),
                  if (netted > 0)
                    StatusBadge(
                      'مقاصة $netted',
                      tone: Tone.accent,
                      icon: Icons.compare_arrows,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ErpButton(
                label: 'تطبيق التسويات',
                icon: Icons.play_arrow_rounded,
                loading: busy,
                loadingLabel: 'جاري التطبيق…',
                onPressed: lines.isEmpty ? null : _run,
              ),
            ],
          ),
        ),
        if (job != null && job.active) ...[gap, _jobBox(job)],
        if (_last != null && !busy) ...[
          const SizedBox(height: 14),
          _lastCard(_last!),
        ],
      ],
    );
  }

  Widget _lastCard(AdjustOutcome out) {
    final s = out.summary ?? AdjustmentsService.summarize(out.results);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('آخر تطبيق'),
        Container(
          decoration: panelDecoration(),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'الإضافات',
                      value: AdjustmentsService.money(s.totalAdded),
                      color: Tw.emerald600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: StatTile(
                      label: 'الخصومات المنفّذة',
                      value: AdjustmentsService.money(s.totalDeducted),
                      color: Tw.indigo600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: StatTile(
                      label: 'المبالغ المستحقة',
                      value: AdjustmentsService.money(s.totalDebt),
                      color: Tw.amber700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${out.results.length} عملية${out.pushed ? ' · مُصدّرة إلى «${out.pushedSheet}»' : ''}',
                      style: Ds.secondary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showResults(out),
                    icon: const Icon(Icons.assignment_outlined, size: 17),
                    label: const Text('التقرير'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _jobBox(AuditJob job) {
    final waiting = job.status == AuditJob.waiting;
    final total = job.stepTotal;
    final done = job.stepNext.clamp(0, total);
    return Container(
      decoration: panelDecoration(border: waiting ? Tw.amber200 : null),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProgressRing(
                value: total > 0 ? done / total : null,
                size: 48,
                color: waiting ? Tw.amber500 : Tw.indigo600,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      waiting
                          ? 'التطبيق متوقف — بانتظار الاتصال'
                          : 'جاري تطبيق التسويات…',
                      style: Ds.title,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      job.progress ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Ds.secondary,
                    ),
                  ],
                ),
              ),
              const InfoTip(
                'يمكنك إغلاق التطبيق: يكمل العمل في الخلفية، وإذا انقطع الإنترنت يُستأنف دون تكرار أي إضافة أو خصم.',
                title: 'العمل في الخلفية',
              ),
            ],
          ),
          if (waiting) ...[
            const SizedBox(height: 8),
            ErpButton(
              label: 'استئناف الآن',
              icon: Icons.play_arrow_rounded,
              kind: ErpButtonKind.amber,
              height: 40,
              fontSize: 13.5,
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
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 6, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('تقرير تطبيق التسويات', style: Ds.title),
                ),
                IconButton(
                  tooltip: 'نسخ الجدول والملخص',
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: AdjustmentsService.copyText(out.results, s),
                      ),
                    );
                    if (context.mounted) {
                      showToast(
                        context,
                        'نُسخ الجدول والملخص — الصقه في Excel.',
                        ToastType.success,
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.content_copy_outlined,
                    size: 20,
                    color: Tw.slate600,
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: Tw.slate500),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'الإضافات',
                        value: AdjustmentsService.money(s.totalAdded),
                        color: Tw.emerald600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: StatTile(
                        label: 'الخصومات المنفّذة',
                        value: AdjustmentsService.money(s.totalDeducted),
                        color: Tw.indigo600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: StatTile(
                        label: 'المبالغ المستحقة',
                        value: AdjustmentsService.money(s.totalDebt),
                        color: Tw.amber700,
                      ),
                    ),
                  ],
                ),
                if (s.debtUsers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Tw.slate600,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text: 'مستحقات على: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Tw.amber800,
                          ),
                        ),
                        TextSpan(text: s.debtUsers.join(' ، ')),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                out.pushed
                    ? ErpButton(
                      label: 'فتح ورقة «${out.pushedSheet}»',
                      icon: Icons.open_in_new,
                      kind: ErpButtonKind.outline,
                      height: 42,
                      fontSize: 13.5,
                      onPressed: _open,
                    )
                    : ActionWithInfo(
                      title: 'تصدير إلى Google Sheets',
                      info:
                          'يكتب التقرير في ورقة جديدة «إضافات وخصومات» في نفس الجدول: القائمة الملصوقة في A–C، ونتيجة كل سطر بجانبه في E–G، والمجاميع تحتها، ثم جدول المقاصات (الإضافة، الخصم، الصافي). معالجة أخرى تُكتب في «إضافات وخصومات 2»… وإذا انقطع الاتصال تُعاد في نفس الورقة.',
                      button: ErpButton(
                        label: 'تصدير إلى ورقة «إضافات وخصومات»',
                        icon: Icons.ios_share_outlined,
                        kind: ErpButtonKind.indigoSoft,
                        height: 42,
                        fontSize: 13.5,
                        loading: _pushing,
                        loadingLabel: 'جاري التصدير…',
                        onPressed: widget.jobId == null ? null : _push,
                      ),
                    ),
              ],
            ),
          ),
          Container(
            color: Tw.slate50,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
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
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: out.results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _ResultRow(out.results[i]),
            ),
          ),
        ],
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
    // ERP badge colours: debt amber, not found / zero salary red, else green.
    final tone =
        st.contains('باقي')
            ? Tone.warning
            : st.contains('غير موجود') ||
                st.contains('سحب ادارة') ||
                st.contains('خطأ')
            ? Tone.danger
            : Tone.success;
    final (bg, fg) = toneColors(tone);
    final border = bg;
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
                      'مقاصة: ${r.settlement}',
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
