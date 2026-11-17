// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../app_services.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'ui_kit.dart';
import 'shell.dart';

/// Asks for a workspace name (new workspace or rename).
Future<String?> askWorkspaceName(
  BuildContext context,
  String title, {
  String initial = '',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder:
        (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('اسم مساحة العمل'),
                ErpTextField(
                  controller: c,
                  hint: 'مثال: شركة النور',
                  maxLength: 60,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, c.text),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
  ).whenComplete(c.dispose);
}

/// Settings → workspaces (owner's request, 2026-11-17): several companies
/// in one app, each with its own cycles, audits, settings and columns, all
/// with the same Google account.
class WorkspacesCard extends StatefulWidget {
  const WorkspacesCard({super.key});
  @override
  State<WorkspacesCard> createState() => _WorkspacesCardState();
}

class _WorkspacesCardState extends State<WorkspacesCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        final m =
            e is StateError
                ? e.message
                : (e is ArgumentError ? '${e.message}' : '$e');
        showToast(context, m, ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = await askWorkspaceName(context, 'مساحة عمل جديدة');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final host = AppScope.read(context).host;
    await _run(() async {
      final w = await host.create(name);
      if (!mounted) return;
      showToast(context, 'تم إنشاء «${w.name}»', ToastType.success);
      // Open it right away; the app reloads on the new workspace.
      await host.switchTo(w.id, tab: AppTabs.settings);
    });
  }

  Future<void> _rename(Workspace w) async {
    final name = await askWorkspaceName(
      context,
      'إعادة تسمية مساحة العمل',
      initial: w.name,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final host = AppScope.read(context).host;
    await _run(() => host.rename(w.id, name));
  }

  Future<void> _delete(Workspace w) async {
    final ok = await confirmDialog(
      context,
      icon: Icons.delete_outline,
      iconColor: Tw.red600,
      iconBg: Tw.red100,
      title: 'حذف مساحة العمل',
      body:
          'سيُحذف من هذا الهاتف كل ما في «${w.name}»: الفترات وحالات التدقيق والإعدادات وربط الحقول. لا يُحذف أي شيء من Google. لا يمكن التراجع.',
      confirmLabel: 'حذف',
      confirmKind: ErpButtonKind.danger,
    );
    if (!ok || !mounted) return;
    final host = AppScope.read(context).host;
    await _run(() async {
      await host.delete(w.id);
      if (mounted) showToast(context, 'تم حذف «${w.name}»', ToastType.success);
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final host = services.host;
    final activeId = services.workspace.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(
          'مساحات العمل',
          icon: Icons.work_outline,
          trailing: InfoTip(
            'لكل مساحة عمل فتراتها وتدقيقها وإعداداتها وربط حقولها، منفصلة تمامًا عن غيرها (مثلًا شركة ثانية). حساب Google مشترك بين كل المساحات. التنقل السريع بينها من القائمة في الشريط العلوي.',
            title: 'مساحات العمل',
          ),
        ),
        GroupList(
          children: [
            for (final w in host.workspaces)
              ListRow(
                title: w.name,
                selected: w.id == activeId,
                titleColor: w.id == activeId ? Tw.indigo700 : null,
                subtitle:
                    w.id == activeId
                        ? const Text('المساحة الحالية')
                        : (w.isMain ? const Text('المساحة الرئيسية') : null),
                leading: Icon(
                  w.id == activeId ? Icons.check_circle : Icons.work_outline,
                  size: 22,
                  color: w.id == activeId ? Tw.indigo600 : Tw.slate400,
                ),
                onTap:
                    _busy || w.id == activeId
                        ? null
                        : () => _run(
                          () => host.switchTo(w.id, tab: AppTabs.settings),
                        ),
                trailing: PopupMenuButton<String>(
                  enabled: !_busy,
                  tooltip: 'إجراءات',
                  icon: const Icon(
                    Icons.more_vert,
                    size: 20,
                    color: Tw.slate500,
                  ),
                  onSelected: (v) {
                    if (v == 'open') {
                      _run(() => host.switchTo(w.id, tab: AppTabs.settings));
                    }
                    if (v == 'rename') _rename(w);
                    if (v == 'delete') _delete(w);
                  },
                  itemBuilder:
                      (_) => [
                        if (w.id != activeId)
                          const PopupMenuItem(
                            value: 'open',
                            height: 44,
                            child: Text('فتح المساحة'),
                          ),
                        const PopupMenuItem(
                          value: 'rename',
                          height: 44,
                          child: Text('إعادة تسمية'),
                        ),
                        if (!w.isMain && w.id != activeId)
                          const PopupMenuItem(
                            value: 'delete',
                            height: 44,
                            child: Text(
                              'حذف',
                              style: TextStyle(color: Tw.red600),
                            ),
                          ),
                      ],
                ),
              ),
            ListRow(
              title: 'مساحة عمل جديدة',
              titleColor: Tw.indigo600,
              leading: const Icon(Icons.add, size: 22, color: Tw.indigo600),
              onTap: _busy ? null : _add,
              trailing:
                  _busy
                      ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                      : null,
            ),
          ],
        ),
      ],
    );
  }
}
