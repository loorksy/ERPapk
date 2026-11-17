// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app_services.dart';
import '../data/app_database.dart';
import '../erp/normalize.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'workspaces_card.dart';

/// Settings → the columns of the open workspace (owner's request,
/// 2026-11-17). Defaults are the columns the app always used; saving them
/// applies them to the audit page right away.
class ColumnsCard extends StatefulWidget {
  const ColumnsCard({super.key});
  @override
  State<ColumnsCard> createState() => _ColumnsCardState();
}

class _ColumnsCardState extends State<ColumnsCard> {
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
      'تم حفظ أعمدة «${services.workspace.name}» وتطبيقها على صفحة التدقيق',
      ToastType.success,
    );
  }

  Widget _pick(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    bool allowAuto = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Tw.slate700),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ErpSelect<String>(
            options: [
              if (allowAuto) const SelectOption('', 'تلقائي'),
              for (final l in _letters) SelectOption(l, l),
            ],
            value: value,
            onChanged: onChanged,
          ),
        ),
      ],
    ),
  );

  Widget _group(String title) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Tw.indigo700,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = _c;
    return ErpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCardHeader(
            icon: FontAwesomeIcons.tableColumns,
            title: 'أعمدة «${services.workspace.name}»',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                c == null
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'الأعمدة الافتراضية لهذه المساحة. تُطبَّق على صفحة التدقيق عند الحفظ، ويمكن تغييرها في أي وقت.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Tw.slate600,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _group('جدول معلومات المستخدمين'),
                        _pick(
                          'رقم المستخدم',
                          c.userInfoUserIdCol,
                          (v) =>
                              setState(() => _c = _with(userInfoUserIdCol: v)),
                        ),
                        _pick(
                          'اسم الوكالة (اسم ورقة الوجهة)',
                          c.userInfoTitleCol,
                          (v) =>
                              setState(() => _c = _with(userInfoTitleCol: v)),
                        ),
                        _pick(
                          'الراتب (يُكتب)',
                          c.userInfoSalaryCol,
                          (v) =>
                              setState(() => _c = _with(userInfoSalaryCol: v)),
                        ),
                        _pick(
                          'الحالة (يُكتب)',
                          c.userInfoStatusCol,
                          (v) =>
                              setState(() => _c = _with(userInfoStatusCol: v)),
                          allowAuto: true,
                        ),
                        _group('ورقة الإدارة'),
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
                        _group('ورقة الوكيل'),
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
                        _group('غير المذكورين'),
                        const FieldLabel('النص (واسم الورقة في جدول الإدارة)'),
                        ErpTextField(controller: _label, maxLength: 60),
                        const SizedBox(height: 10),
                        const FieldLabel(
                          'أعمدة إضافية يُكتب فيها رقم المستخدم',
                        ),
                        ErpTextField(controller: _idCols, hint: 'A', ltr: true),
                        const SizedBox(height: 10),
                        const FieldLabel('أعمدة إضافية يُكتب فيها النص'),
                        ErpTextField(
                          controller: _labelCols,
                          hint: 'E',
                          ltr: true,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'عند «تدقيق غير المذكورين» يُكتب الرقم في عمود رقم المستخدم وفي هذه الأعمدة، والنص في عمود اسم الوكالة وفي أعمدة النص.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Tw.slate500,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ErpButton(
                          label: 'حفظ الأعمدة',
                          icon: FontAwesomeIcons.floppyDisk,
                          kind: ErpButtonKind.indigo,
                          height: 42,
                          loading: _saving,
                          onPressed: _save,
                        ),
                        const SizedBox(height: 8),
                        ErpButton(
                          label: 'استعادة الأعمدة الافتراضية',
                          icon: FontAwesomeIcons.arrowRotateLeft,
                          kind: ErpButtonKind.outline,
                          height: 40,
                          fontSize: 12.5,
                          onPressed: () => _show(const WorkspaceColumns()),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}
