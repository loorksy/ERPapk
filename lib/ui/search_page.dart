// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../data/app_database.dart';
import '../erp/js_compat.dart';
import '../erp/payroll_audit_engine.dart';
import '../services/search_service.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'ui_kit.dart';

/// ERP «البحث والتدقيق» page (`views/partials/search.ejs`).
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.active});
  final bool active;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  int _revision = -1;
  List<Cycle> _cycles = const [];
  String _cycleId = '';
  final _userId = TextEditingController();
  final _discount = TextEditingController();
  final _newSheet = TextEditingController();
  bool _global = false;
  Timer? _debounce;

  SearchOutcome? _outcome;
  bool _global0 = false;
  final _cardKey = GlobalKey();

  // Selective audit
  bool _auditOpen = false;
  String _auditMemberId = '';
  String _auditLogical = '';
  List<String> _targetSheets = const [];
  String? _targetMessage;
  String _targetSheet = '';
  String _agentColor = defaultAgentColor;
  String _mgmtColor = defaultManagementColor;
  bool _executing = false;

  AppServices get _s => AppScope.read(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (services.cyclesRevision != _revision) {
      _revision = services.cyclesRevision;
      _loadCycles();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _userId.dispose();
    _discount.dispose();
    _newSheet.dispose();
    super.dispose();
  }

  Future<void> _loadCycles() async {
    final list = await _s.db.listCycles();
    if (!mounted) return;
    setState(() {
      _cycles = list;
      if (!list.any((c) => '${c.id}' == _cycleId)) {
        _cycleId = list.isEmpty ? '' : '${list.first.id}';
      }
    });
  }

  void _debounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _paste() async {
    final t = await pasteText();
    if (t == null || t.isEmpty) return;
    _userId.text = t;
    _debounced();
  }

  Future<void> _runSearch() async {
    final userId = _userId.text.trim();
    final rate = jsParseFloat(_discount.text.trim());
    final discount = rate.isNaN ? 0.0 : rate;
    if ((_cycleId.isEmpty && !_global) || userId.isEmpty) return;
    final outcome =
        _global
            ? await _s.search.searchAcrossCycles(userId, discount)
            : await _s.search.searchUser(int.parse(_cycleId), userId, discount);
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _global0 = _global;
      _auditOpen = false;
    });
    if (!outcome.success) {
      final msg = outcome.message!;
      showToast(
        context,
        msg,
        msg.contains('غير موجود') ? ToastType.info : ToastType.error,
      );
      return;
    }
    if (!_global && outcome.hits.isNotEmpty && outcome.hits.first.canAudit) {
      _openAudit(outcome.hits.first.memberId, outcome.hits.first.logicalStatus);
    }
    showToast(context, 'تم جلب نتيجة البحث', ToastType.success);
  }

  Future<void> _openAudit(String memberId, String logical) async {
    setState(() {
      _auditOpen = true;
      _auditMemberId = memberId;
      _auditLogical = logical;
      _agentColor = defaultAgentColor;
      _mgmtColor = defaultManagementColor;
      _targetSheet = '';
      _newSheet.clear();
      _targetSheets = const [];
      _targetMessage = '— جاري جلب الأوراق —';
    });
    if (_cycleId.isEmpty) return;
    try {
      final sheets = await _s.search.cycleSheets(int.parse(_cycleId));
      if (!mounted) return;
      setState(() {
        _targetSheets = sheets;
        _targetMessage =
            sheets.isEmpty ? 'لا توجد أوراق في جدول الإدارة لهذه الفترة' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _targetMessage = e.toString());
    }
  }

  Future<void> _execute() async {
    if (_cycleId.isEmpty) {
      showToast(
        context,
        'اختر الفترة التي تريد تدقيق المستخدم فيها',
        ToastType.error,
      );
      return;
    }
    final newTitle = _newSheet.text.trim();
    final target = newTitle.isNotEmpty ? newTitle : _targetSheet;
    if (target.isEmpty) {
      showToast(
        context,
        'اختر ورقة هدف أو اكتب اسماً لورقة جديدة',
        ToastType.error,
      );
      return;
    }
    setState(() => _executing = true);
    final r = await _s.search.executeIndividual(
      cycleId: int.parse(_cycleId),
      memberIdRaw: _auditMemberId,
      targetSheetTitle: target,
      createIfMissing: newTitle.isNotEmpty,
      agentColor: _agentColor,
      managementColor: _mgmtColor,
    );
    if (!mounted) return;
    setState(() => _executing = false);
    showToast(
      context,
      r.message,
      r.success ? ToastType.success : ToastType.error,
    );
    if (r.success) {
      setState(() => _auditOpen = false);
      _s.cyclesChanged();
      _debounced();
    }
  }

  String _cardText() {
    final o = _outcome;
    if (o == null || !o.success) return o?.message ?? '';
    final b = StringBuffer();
    final first = o.hits.first;
    b.writeln('رقم المستخدم: ${first.memberId}');
    final name = o.hits
        .map((h) => h.name)
        .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null);
    if (name != null) b.writeln('الاسم: $name');
    for (final h in o.hits) {
      if (_global0) b.writeln('— الفترة: ${h.cycleName}');
      b.writeln('التصنيف: ${h.logicalStatus}');
      b.writeln('الراتب قبل الخصم: ${jsNumberToString(h.salaryBefore)}');
      b.writeln('الراتب بعد الخصم: ${jsNumberToString(h.salaryAfter)}');
      b.writeln(
        'حالة التدقيق: ${h.auditStatus}${h.auditSource != null ? ' — ${h.auditSource}' : ''}',
      );
    }
    return b.toString().trim();
  }

  Future<void> _copyCard() async {
    final text = _cardText();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showToast(context, 'تم نسخ النتائج كبطاقة نصية', ToastType.success);
    }
  }

  Future<void> _downloadImage() async {
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ البطاقة كصورة',
        fileName: 'بطاقة-${_userId.text.trim()}.png',
        type: FileType.image,
        bytes: data.buffer.asUint8List(),
      );
      if (saved != null && mounted) {
        showToast(context, 'تم حفظ الصورة', ToastType.success);
      }
    } catch (_) {
      if (mounted) showToast(context, 'تعذر حفظ الصورة', ToastType.error);
    }
  }

  // ------------------------------------------------------------------ UI
  //
  // «Compact Fluid UI» (3.0): search-first — one field with paste, the
  // scope (this period / all periods) as a segmented control, then the
  // member card. Same queries, selective audit, copy and image export.

  @override
  Widget build(BuildContext context) => ListView(
    padding: Ds.pagePadding,
    children: [
      _criteria(),
      if (_outcome != null) ...[const SizedBox(height: 14), _resultCard()],
      if (_outcome == null)
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: Column(
            children: [
              Icon(Icons.manage_search, size: 40, color: Tw.slate300),
              SizedBox(height: 8),
              Text(
                'أدخل رقم المستخدم للاستعلام عن حالته وراتبه',
                style: TextStyle(fontSize: 13, color: Tw.slate400),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _criteria() => Container(
    decoration: panelDecoration(),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _userId,
          keyboardType: TextInputType.number,
          onChanged: (_) => _debounced(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'رقم المستخدم',
            fillColor: Tw.slate50,
            prefixIcon: const Icon(Icons.search, size: 20, color: Tw.slate400),
            suffixIcon: IconButton(
              tooltip: 'لصق',
              onPressed: _paste,
              icon: const Icon(
                Icons.content_paste_outlined,
                size: 19,
                color: Tw.slate500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Segmented(
                options: const ['هذه الفترة', 'كل الفترات'],
                selected: _global ? 1 : 0,
                onChanged: (i) {
                  setState(() => _global = i == 1);
                  _debounced();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: TextField(
                controller: _discount,
                textDirection: TextDirection.ltr,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => _debounced(),
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '0',
                  prefixIcon: Icon(Icons.percent, size: 16, color: Tw.slate400),
                  prefixIconConstraints: BoxConstraints(minWidth: 30),
                ),
              ),
            ),
            const InfoTip(
              'يُستعلم برقم المستخدم في فترة الرواتب المختارة، أو في كل الفترات. يقرأ الاستعلام آخر مزامنة للفترة (من التدقيق أو المزامنة التلقائية). النسبة % خصم يُطبَّق على الراتب المعروض. من النتيجة يمكن التدقيق الانتقائي لمستخدم واحد، ونسخ البطاقة أو حفظها كصورة.',
              title: 'الاستعلام',
            ),
          ],
        ),
        if (!_global) ...[
          const SizedBox(height: 8),
          ErpSelect<String>(
            muted: true,
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
              setState(() => _cycleId = v);
              _debounced();
            },
          ),
        ],
      ],
    ),
  );

  Widget _resultCard() {
    final o = _outcome!;
    return Container(
      decoration: panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: _resultBody(o),
            ),
          ),
          if (o.success)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Tw.slate200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _copyCard,
                      icon: const Icon(Icons.content_copy_outlined, size: 17),
                      label: const Text('نسخ كبطاقة'),
                    ),
                  ),
                  Container(width: 1, height: 24, color: Tw.slate200),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _downloadImage,
                      icon: const Icon(Icons.image_outlined, size: 17),
                      label: const Text('حفظ كصورة'),
                    ),
                  ),
                ],
              ),
            ),
          if (_auditOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _auditOptions(),
            ),
        ],
      ),
    );
  }

  Widget _kv(String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [Expanded(child: Text(label, style: Ds.secondary)), value],
    ),
  );

  Widget _num(double v) => Text(
    jsNumberToString(v),
    textDirection: TextDirection.ltr,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: Tw.slate900,
    ),
  );

  Widget _auditBadge(CycleSearchHit h) => StatusBadge(
    h.auditStatus,
    tone: h.auditStatus == 'مدقق' ? Tone.success : Tone.warning,
    icon: h.auditStatus == 'مدقق' ? Icons.check : Icons.schedule,
  );

  Widget _hitDetails(CycleSearchHit h) => Column(
    children: [
      _kv('التصنيف', StatusBadge(h.logicalStatus, tone: Tone.accent)),
      _kv('الراتب قبل الخصم', _num(h.salaryBefore)),
      _kv('الراتب بعد الخصم', _num(h.salaryAfter)),
      _kv('حالة التدقيق', _auditBadge(h)),
      if (h.auditSource != null)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(h.auditSource!, style: Ds.secondary),
        ),
    ],
  );

  Widget _resultBody(SearchOutcome o) {
    if (!o.success) {
      return Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: Tw.amber700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              o.message!,
              style: const TextStyle(
                color: Tw.amber800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }
    final first = o.hits.first;
    final name = o.hits
        .map((h) => h.name)
        .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const IconChip(
              Icons.person_outline,
              size: 40,
              color: Tw.indigo600,
              bg: Tw.indigo50,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first.memberId,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Tw.slate900,
                    ),
                  ),
                  if (name != null)
                    Text(name, style: Ds.secondary, maxLines: 1),
                ],
              ),
            ),
            if (_global0)
              StatusBadge('${o.hits.length} فترة', icon: Icons.layers_outlined),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 4),
        if (!_global0)
          _hitDetails(first)
        else
          for (final h in o.hits)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: panelDecoration(color: Tw.slate50),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        size: 16,
                        color: Tw.slate500,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          h.cycleName,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (h.canAudit)
                        TextButton(
                          onPressed: () {
                            setState(() => _cycleId = '${h.cycleId}');
                            _openAudit(h.memberId, h.logicalStatus);
                          },
                          child: const Text('تدقيق انتقائي'),
                        ),
                    ],
                  ),
                  _hitDetails(h),
                ],
              ),
            ),
      ],
    );
  }

  Widget _auditOptions() {
    final isAgent = _auditLogical.startsWith(statusAgent);
    final isMgmt = _auditLogical.startsWith(statusManagement);
    final showAgent = isAgent || !isMgmt;
    final showMgmt = isMgmt || !isAgent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: panelDecoration(color: Tw.slate50),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'خيارات التدقيق الانتقائي',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Tw.slate800,
                  ),
                ),
              ),
              InfoTip(
                'اختر ورقة في جدول الإدارة أو اكتب اسماً لإنشاء ورقة جديدة في الفترة الحالية. يُلحق صف المستخدم بالورقة ويُلوَّن، وتُلوَّن صفوفه الأصلية في الإدارة والوكيل، وتُسجَّل حالته «تدقيق من أداة البحث».',
                title: 'التدقيق الانتقائي',
              ),
            ],
          ),
          const SizedBox(height: 10),
          const FieldLabel(
            'ورقة الهدف في جدول الإدارة',
            small: true,
            bold: true,
          ),
          ErpSelect<String>(
            thick: true,
            options: [
              SelectOption('', _targetMessage ?? '— اختر ورقة أو أنشئ جديدة —'),
              for (final s in _targetSheets) SelectOption(s, s),
            ],
            value: _targetSheet,
            onChanged: (v) => setState(() => _targetSheet = v),
          ),
          const SizedBox(height: 6),
          ErpTextField(controller: _newSheet, hint: 'اسم ورقة جديدة (اختياري)'),
          const SizedBox(height: 12),
          if (showAgent) ...[
            const FieldLabel('لون سحب الوكيل', small: true, bold: true),
            ColorField(
              value: _agentColor,
              onChanged: (v) => setState(() => _agentColor = v),
            ),
            const SizedBox(height: 12),
          ],
          if (showMgmt) ...[
            const FieldLabel('لون سحب الإدارة', small: true, bold: true),
            ColorField(
              value: _mgmtColor,
              onChanged: (v) => setState(() => _mgmtColor = v),
            ),
            const SizedBox(height: 12),
          ],
          ErpButton(
            label: 'تنفيذ التدقيق الانتقائي',
            icon: Icons.check_circle_outline,
            loading: _executing,
            loadingLabel: 'جاري التنفيذ...',
            fontSize: 13,
            onPressed: _execute,
          ),
        ],
      ),
    );
  }
}

/// A two-option segmented control (scope of the inquiry).
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Tw.slate100,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        for (var i = 0; i < options.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: i == selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: i == selected ? Border.all(color: Tw.slate200) : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  options[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        i == selected ? FontWeight.w700 : FontWeight.w500,
                    color: i == selected ? Tw.indigo700 : Tw.slate500,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
