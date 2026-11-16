// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app_services.dart';
import '../data/app_database.dart';
import '../erp/js_compat.dart';
import '../erp/payroll_audit_engine.dart';
import '../services/search_service.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';

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
            sheets.isEmpty ? 'لا توجد أوراق في جدول الإدارة لهذه الدورة' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _targetMessage = e.toString());
    }
  }

  Future<void> _execute() async {
    if (_cycleId.isEmpty) {
      showToast(
        context,
        'اختر الدورة التي تريد تدقيق المستخدم بها',
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
      if (_global0) b.writeln('— الدورة: ${h.cycleName}');
      b.writeln('الحالة المنطقية: ${h.logicalStatus}');
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

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: [
      const PageHeading(
        icon: FontAwesomeIcons.magnifyingGlass,
        title: 'البحث والتدقيق',
        subtitle:
            'استعلام عن مستخدم في الدورة أو عبر كل الدورات — بنفس أسلوب واجهة النظام',
      ),
      const SizedBox(height: 24),
      _criteria(),
      if (_outcome != null) ...[const SizedBox(height: 24), _resultCard()],
    ],
  );

  Widget _sectionHeader(
    FaIconData icon,
    String title, {
    List<Widget> actions = const [],
    Color from = Tw.slate50,
  }) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [from, Colors.white],
      ),
      border: const Border(bottom: BorderSide(color: Tw.slate100)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FaIcon(icon, size: 13, color: Tw.indigo600),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Tw.slate800,
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: actions),
        ],
      ],
    ),
  );

  Widget _criteria() => ErpCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(FontAwesomeIcons.sliders, 'معايير البحث'),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('الدورة المالية', small: true, bold: true),
              ErpSelect<String>(
                thick: true,
                muted: true,
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
                  setState(() => _cycleId = v);
                  _debounced();
                },
              ),
              const SizedBox(height: 16),
              const FieldLabel('بيانات البحث', small: true, bold: true),
              Row(
                children: [
                  Expanded(
                    child: ErpTextField(
                      controller: _userId,
                      thick: true,
                      hint: 'أدخل رقم المستخدم',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _debounced(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: ErpButton(
                      label: 'لصق',
                      icon: FontAwesomeIcons.paste,
                      kind: ErpButtonKind.outline,
                      height: 48,
                      fontSize: 12,
                      onPressed: _paste,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: Tw.slate100),
              ),
              Row(
                children: [
                  const Text(
                    'خصم %',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Tw.slate600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    child: ErpTextField(
                      controller: _discount,
                      thick: true,
                      hint: '0',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => _debounced(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xccf8fafc),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tw.slate200),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'البحث الشامل (كل الدورات)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Tw.slate700,
                        ),
                      ),
                    ),
                    Switch(
                      value: _global,
                      activeTrackColor: Tw.indigo600,
                      inactiveTrackColor: Tw.slate600,
                      inactiveThumbColor: Colors.white,
                      onChanged: (v) {
                        setState(() => _global = v);
                        _debounced();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _resultCard() {
    final o = _outcome!;
    return ErpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            FontAwesomeIcons.userTag,
            'نتيجة البحث',
            from: const Color(0x80eef2ff),
            actions: [
              Expanded(
                child: ErpButton(
                  label: 'نسخ كبطاقة',
                  icon: FontAwesomeIcons.copy,
                  kind: ErpButtonKind.outline,
                  height: 40,
                  fontSize: 12,
                  onPressed: _copyCard,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ErpButton(
                  label: 'تنزيل كصورة',
                  icon: FontAwesomeIcons.image,
                  kind: ErpButtonKind.indigoSoft,
                  height: 40,
                  fontSize: 12,
                  onPressed: _downloadImage,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(
                  key: _cardKey,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(4),
                    child: _resultBody(o),
                  ),
                ),
                if (_auditOpen) ...[
                  const SizedBox(height: 16),
                  _auditOptions(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {Widget? extra}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 14, color: Tw.slate700, height: 1.5),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Tw.slate600,
            ),
          ),
          TextSpan(text: value),
          if (extra != null) WidgetSpan(child: extra),
        ],
      ),
    ),
  );

  Widget _code(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: Tw.slate100,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      textDirection: TextDirection.ltr,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    ),
  );

  Widget _resultBody(SearchOutcome o) {
    if (!o.success) {
      return Text(
        o.message!,
        style: const TextStyle(color: Tw.amber700, fontWeight: FontWeight.w500),
      );
    }
    final first = o.hits.first;
    final name = o.hits
        .map((h) => h.name)
        .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null);
    String audit(CycleSearchHit h) =>
        h.auditStatus + (h.auditSource != null ? ' — ${h.auditSource}' : '');
    final children = <Widget>[
      Row(
        children: [
          const Text(
            'رقم المستخدم: ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Tw.slate600,
            ),
          ),
          _code(first.memberId),
        ],
      ),
      const SizedBox(height: 6),
      if (name != null) _line('الاسم', name),
    ];
    if (_global0) {
      children.add(
        Text(
          'عدد الدورات التي ظهر بها هذا المستخدم: ${o.hits.length}',
          style: const TextStyle(fontSize: 12, color: Tw.slate500),
        ),
      );
      children.add(const SizedBox(height: 12));
      for (final h in o.hits) {
        children.add(
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tw.slate200),
              gradient: const LinearGradient(
                colors: [Tw.slate50, Colors.white],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _line('الدورة', h.cycleName),
                _line('الحالة المنطقية', h.logicalStatus),
                _line('الراتب قبل الخصم', jsNumberToString(h.salaryBefore)),
                _line('الراتب بعد الخصم', jsNumberToString(h.salaryAfter)),
                _line('حالة التدقيق', audit(h)),
                if (h.canAudit) ...[
                  const SizedBox(height: 8),
                  ErpButton(
                    label: 'تدقيق هذه الدورة',
                    icon: FontAwesomeIcons.wandMagicSparkles,
                    height: 44,
                    fontSize: 13,
                    onPressed: () {
                      setState(() => _cycleId = '${h.cycleId}');
                      _openAudit(h.memberId, h.logicalStatus);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      }
    } else {
      children.addAll([
        _line('الحالة المنطقية', first.logicalStatus),
        _line('الراتب قبل الخصم', jsNumberToString(first.salaryBefore)),
        _line('الراتب بعد الخصم', jsNumberToString(first.salaryAfter)),
        _line('حالة التدقيق', audit(first)),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _auditOptions() {
    final isAgent = _auditLogical.startsWith(statusAgent);
    final isMgmt = _auditLogical.startsWith(statusManagement);
    final showAgent = isAgent || !isMgmt;
    final showMgmt = isMgmt || !isAgent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x99eef2ff),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tw.indigo100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'خيارات التدقيق الانتقائي',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Tw.slate800,
            ),
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
            icon: FontAwesomeIcons.circleCheck,
            loading: _executing,
            loadingLabel: 'جاري التنفيذ...',
            fontSize: 13,
            onPressed: _execute,
          ),
          const SizedBox(height: 6),
          const Text(
            'اختر ورقة في جدول الإدارة أو اكتب اسماً لإنشاء ورقة جديدة في الدورة الحالية.',
            style: TextStyle(fontSize: 11, color: Tw.slate500),
          ),
        ],
      ),
    );
  }
}
