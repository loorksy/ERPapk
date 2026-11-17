// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/app_database.dart';
import '../erp/normalize.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'ui_kit.dart';

/// Settings → the columns of the open workspace (owner's request,
/// 2026-11-17). Defaults are the columns the app always used; saving them
/// applies them to the audit page right away.
class ColumnsPage extends StatefulWidget {
  const ColumnsPage({super.key});
  @override
  State<ColumnsPage> createState() => _ColumnsPageState();
}

class _ColumnsPageState extends State<ColumnsPage> {
  WorkspaceColumns? _c;
  final _label = TextEditingController();
  final _idCols = TextEditingController();
  final _labelCols = TextEditingController();
  bool _saving = false;

  static final _letters = [for (var i = 0; i < 52; i++) columnIndexToLetter(i)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _label.dispose();
    _idCols.dispose();
    _labelCols.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await AppScope.read(context).db.getWorkspaceColumns();
    if (mounted) _show(c);
  }

  void _show(WorkspaceColumns c) {
    setState(() {
      _c = c;
      _label.text = c.unmentionedLabel;
      _idCols.text = c.unmentionedIdCols.join(', ');
      _labelCols.text = c.unmentionedLabelCols.join(', ');
    });
  }

  WorkspaceColumns _with({
    String? userInfoUserIdCol,
    String? userInfoTitleCol,
    String? userInfoSalaryCol,
    String? userInfoStatusCol,
    String? mgmtUserIdCol,
    String? agentUserIdCol,
    String? agentSalaryCol,
    String? agentNameCol,
    String? mgmtShareCol,
    String? unmentionedColor,
  }) {
    final c = _c!;
    return WorkspaceColumns(
      userInfoUserIdCol: userInfoUserIdCol ?? c.userInfoUserIdCol,
      userInfoTitleCol: userInfoTitleCol ?? c.userInfoTitleCol,
      userInfoSalaryCol: userInfoSalaryCol ?? c.userInfoSalaryCol,
      userInfoStatusCol: userInfoStatusCol ?? c.userInfoStatusCol,
      mgmtUserIdCol: mgmtUserIdCol ?? c.mgmtUserIdCol,
      agentUserIdCol: agentUserIdCol ?? c.agentUserIdCol,
      agentSalaryCol: agentSalaryCol ?? c.agentSalaryCol,
      agentNameCol: agentNameCol ?? c.agentNameCol,
      mgmtShareCol: mgmtShareCol ?? c.mgmtShareCol,
      unmentionedLabel: c.unmentionedLabel,
      unmentionedIdCols: c.unmentionedIdCols,
      unmentionedLabelCols: c.unmentionedLabelCols,
      unmentionedColor: unmentionedColor ?? c.unmentionedColor,
    );
  }

  Future<void> _save() async {
    final c = _c;
    if (c == null) return;
    final idCols = WorkspaceColumns.parseColumnList(_idCols.text);
    final labelCols = WorkspaceColumns.parseColumnList(_labelCols.text);
    if (idCols == null || labelCols == null) {
      showToast(
        context,
        'اكتب حروف أعمدة صحيحة مفصولة بفاصلة (مثل: A, E).',
        ToastType.error,
      );
      return;
    }
    final label = _label.text.trim();
    final next = WorkspaceColumns(
      userInfoUserIdCol: c.userInfoUserIdCol,
      userInfoTitleCol: c.userInfoTitleCol,
      userInfoSalaryCol: c.userInfoSalaryCol,
      userInfoStatusCol: c.userInfoStatusCol,
      mgmtUserIdCol: c.mgmtUserIdCol,
      agentUserIdCol: c.agentUserIdCol,
      agentSalaryCol: c.agentSalaryCol,
      agentNameCol: c.agentNameCol,
      mgmtShareCol: c.mgmtShareCol,
      unmentionedLabel: label.isEmpty ? 'غير مذكور' : label,
      unmentionedIdCols: idCols,
      unmentionedLabelCols: labelCols,
      unmentionedColor: c.unmentionedColor,
    );
    final problem = next.validate();
    if (problem != null) {
      showToast(context, problem, ToastType.error);
      return;
    }
    setState(() => _saving = true);
    final services = AppScope.read(context);
    await services.db.saveWorkspaceColumns(next);
    services.columnsChanged();
    if (!mounted) return;
    setState(() => _saving = false);
    _show(next);
    showToast(
      context,
      'حُفظ ربط حقول «${services.workspace.name}» وطُبِّق على شاشة التدقيق',
      ToastType.success,
    );
  }

  /// One mapping row: label and a compact column picker.
  Widget _pick(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool allowAuto = false,
  }) => ListRow(
    title: label,
    trailing: SizedBox(
      width: 104,
      child: ErpSelect<String>(
        muted: true,
        options: [
          if (allowAuto) const SelectOption('', 'تلقائي'),
          for (final l in _letters) SelectOption(l, l),
        ],
        value: value,
        onChanged: onChanged,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = _c;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Tw.slate50,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: const Border(bottom: BorderSide(color: Tw.slate200)),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ربط حقول البيانات',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Tw.slate900,
                ),
              ),
              Text(services.workspace.name, style: Ds.secondary),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _show(const WorkspaceColumns()),
              child: const Text('الافتراضي'),
            ),
            const InfoTip(
              'الأعمدة الافتراضية لهذه المساحة. تُطبَّق على شاشة التدقيق عند الحفظ، ويمكن تغييرها في أي وقت.\n\nعند «تدقيق غير المذكورين» يُكتب الرقم في عمود رقم المستخدم وفي «أعمدة إضافية للرقم»، والنص في عمود اسم الوكالة وفي «أعمدة إضافية للنص».',
              title: 'ربط حقول البيانات',
            ),
          ],
        ),
        body:
            c == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                  padding: Ds.pagePadding,
                  children: [
                    const SectionLabel(
                      'بيانات المستخدمين',
                      icon: Icons.grid_on_outlined,
                    ),
                    GroupList(
                      children: [
                        _pick(
                          'رقم المستخدم',
                          c.userInfoUserIdCol,
                          (v) =>
                              setState(() => _c = _with(userInfoUserIdCol: v)),
                        ),
                        _pick(
                          'اسم الوكالة (ورقة الوجهة)',
                          c.userInfoTitleCol,
                          (v) =>
                              setState(() => _c = _with(userInfoTitleCol: v)),
                        ),
                        _pick(
                          'كتابة الراتب',
                          c.userInfoSalaryCol,
                          (v) =>
                              setState(() => _c = _with(userInfoSalaryCol: v)),
                        ),
                        _pick(
                          'كتابة الحالة',
                          c.userInfoStatusCol,
                          (v) =>
                              setState(() => _c = _with(userInfoStatusCol: v)),
                          allowAuto: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const SectionLabel(
                      'جدول الإدارة',
                      icon: Icons.apartment_outlined,
                    ),
                    GroupList(
                      children: [
                        _pick(
                          'رقم المستخدم',
                          c.mgmtUserIdCol,
                          (v) => setState(() => _c = _with(mgmtUserIdCol: v)),
                        ),
                        _pick(
                          'مبلغ الوكيل الفرعي',
                          c.mgmtShareCol,
                          (v) => setState(() => _c = _with(mgmtShareCol: v)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const SectionLabel(
                      'جدول الوكيل',
                      icon: Icons.badge_outlined,
                    ),
                    GroupList(
                      children: [
                        _pick(
                          'رقم المستخدم',
                          c.agentUserIdCol,
                          (v) => setState(() => _c = _with(agentUserIdCol: v)),
                        ),
                        _pick(
                          'الراتب',
                          c.agentSalaryCol,
                          (v) => setState(() => _c = _with(agentSalaryCol: v)),
                        ),
                        _pick(
                          'الاسم',
                          c.agentNameCol,
                          (v) => setState(() => _c = _with(agentNameCol: v)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const SectionLabel(
                      'غير المذكورين',
                      icon: Icons.person_add_alt_outlined,
                    ),
                    Container(
                      decoration: panelDecoration(),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldHeader(
                            'النص (واسم الورقة في جدول الإدارة)',
                          ),
                          ErpTextField(controller: _label, maxLength: 60),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const FieldHeader('أعمدة إضافية للرقم'),
                                    ErpTextField(
                                      controller: _idCols,
                                      hint: 'A',
                                      ltr: true,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const FieldHeader('أعمدة إضافية للنص'),
                                    ErpTextField(
                                      controller: _labelCols,
                                      hint: 'E',
                                      ltr: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const FieldHeader(
                            'لون سجلات الإدارة المنقولة',
                            info:
                                'لون السجلات التي ينقلها إجراء «٢. نقل سجلات الإدارة غير الملوّنة»: تُلوَّن به في جدول الإدارة وفي ورقة «غير مذكور» (هذه السجلات فقط) لتمييزها. لا يظهر في شاشة التدقيق.',
                          ),
                          ColorField(
                            value: c.unmentionedColor,
                            onChanged:
                                (v) => setState(
                                  () => _c = _with(unmentionedColor: v),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        bottomNavigationBar:
            c == null
                ? null
                : SafeArea(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Tw.slate200)),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: ErpButton(
                      label: 'حفظ ربط الحقول',
                      icon: Icons.save_outlined,
                      loading: _saving,
                      onPressed: _save,
                    ),
                  ),
                ),
      ),
    );
  }
}
