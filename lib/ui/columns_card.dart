// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/app_database.dart';
import '../erp/normalize.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'help.dart';
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
    // Back to Settings, like the mockup.
    Navigator.of(context).maybePop();
  }

  /// One mapping row (`.frow`): label and a compact column picker.
  Widget _pick(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool allowAuto = false,
  }) => FormRow(
    label,
    CompactSelect<String>(
      options: [
        if (allowAuto) const SelectOption('', 'تلقائي'),
        for (final l in _letters) SelectOption(l, l),
      ],
      value: value,
      onChanged: onChanged,
    ),
  );

  Widget _section(String title, Widget child, {Widget? after}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionLabel(title), child, if (after != null) after],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = _c;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: Tw.paper,
        child:
            c == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    // `.topbar`: back to Settings, «الافتراضي», «؟».
                    SizedBox(
                      height: 54,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.chevron_right, size: 22),
                              label: const Text(
                                'الإعدادات',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            const Spacer(),
                            HelpButton(
                              title: 'ربط حقول البيانات',
                              items: () => mappingHelp,
                            ),
                            TextButton(
                              onPressed: () {
                                _show(const WorkspaceColumns());
                                showToast(
                                  context,
                                  'أُعيدت الأعمدة الافتراضية. اضغط «حفظ ربط الحقول» لتطبيقها.',
                                  ToastType.info,
                                );
                              },
                              child: const Text('الافتراضي'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ربط حقول البيانات', style: Ds.screenTitle),
                          const SizedBox(height: 4),
                          Text(
                            'أعمدة «${services.workspace.name}». تُطبَّق على شاشة التدقيق عند الحفظ.',
                            style: TextStyle(fontSize: 14.5, color: Tw.ink2),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      'بيانات المستخدمين',
                      FormRows(
                        onSurface: false,
                        children: [
                          _pick(
                            'رقم المستخدم',
                            c.userInfoUserIdCol,
                            (v) => setState(
                              () => _c = _with(userInfoUserIdCol: v),
                            ),
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
                            (v) => setState(
                              () => _c = _with(userInfoSalaryCol: v),
                            ),
                          ),
                          _pick(
                            'كتابة الحالة',
                            c.userInfoStatusCol,
                            (v) => setState(
                              () => _c = _with(userInfoStatusCol: v),
                            ),
                            allowAuto: true,
                          ),
                        ],
                      ),
                    ),
                    _section(
                      'جدول الإدارة',
                      FormRows(
                        onSurface: false,
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
                    ),
                    _section(
                      'جدول الوكيل',
                      FormRows(
                        onSurface: false,
                        children: [
                          _pick(
                            'رقم المستخدم',
                            c.agentUserIdCol,
                            (v) =>
                                setState(() => _c = _with(agentUserIdCol: v)),
                          ),
                          _pick(
                            'الراتب',
                            c.agentSalaryCol,
                            (v) =>
                                setState(() => _c = _with(agentSalaryCol: v)),
                          ),
                          _pick(
                            'الاسم',
                            c.agentNameCol,
                            (v) => setState(() => _c = _with(agentNameCol: v)),
                          ),
                        ],
                      ),
                    ),
                    _section(
                      'غير المذكورين',
                      FormRows(
                        onSurface: false,
                        children: [
                          FormRow(
                            'النص (واسم الورقة في جدول الإدارة)',
                            ErpTextField(
                              controller: _label,
                              thick: true,
                              maxLength: 60,
                            ),
                            block: true,
                          ),
                          FormRow(
                            'أعمدة إضافية للرقم',
                            ErpTextField(
                              controller: _idCols,
                              thick: true,
                              hint: 'A',
                              ltr: true,
                            ),
                            block: true,
                          ),
                          FormRow(
                            'أعمدة إضافية للنص',
                            ErpTextField(
                              controller: _labelCols,
                              thick: true,
                              hint: 'E',
                              ltr: true,
                            ),
                            block: true,
                          ),
                          FormRow(
                            'لون سجلات الإدارة المنقولة',
                            ColorSwatchButton(
                              value: c.unmentionedColor,
                              onChanged:
                                  (v) => setState(
                                    () => _c = _with(unmentionedColor: v),
                                  ),
                            ),
                          ),
                        ],
                      ),
                      after: Caption(
                        'يلوّن به إجراء «٢. نقل سجلات الإدارة غير الملوّنة» الصفوف التي ينقلها، في ورقة الإدارة ونسخها في «${_label.text.trim().isEmpty ? 'غير مذكور' : _label.text.trim()}» فقط.',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: ErpButton(
                        label: 'حفظ ربط الحقول',
                        loading: _saving,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}
