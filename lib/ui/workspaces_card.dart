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
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (initial.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'لكل مساحة فتراتها وتدقيقها وإعداداتها، منفصلة عن غيرها.',
                    ),
                  ),
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

  /// `wsMenuSheet`: open, rename, delete (not the main workspace).
  Future<void> _menu(Workspace w, int activeId) async {
    final host = AppScope.read(context).host;
    final v = await showAppSheet<String>(
      context,
      (ctx) => AppSheet(
        title: w.name,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (w.id != activeId)
              ChoiceTile(
                icon: Icons.work_outline,
                label: 'فتح المساحة',
                onTap: () => Navigator.pop(ctx, 'open'),
              ),
            ChoiceTile(
              icon: Icons.edit_outlined,
              label: 'إعادة تسمية',
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            if (!w.isMain && w.id != activeId)
              ChoiceTile(
                icon: Icons.delete_outline,
                label: 'حذف',
                danger: true,
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            if (w.isMain)
              const Caption(
                'المساحة الرئيسية لا تُحذف، وفيها بيانات النسخ السابقة.',
              )
            else if (w.id == activeId)
              const Caption('انتقل إلى مساحة عمل أخرى قبل حذف هذه.'),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'open') {
      _run(() => host.switchTo(w.id, tab: AppTabs.settings));
    }
    if (v == 'rename') _rename(w);
    if (v == 'delete') _delete(w);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final host = services.host;
    final activeId = services.workspace.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('مساحات العمل'),
        GroupList(
          children: [
            for (final w in host.workspaces)
              ListRow(
                title: w.name,
                subtitle:
                    w.id == activeId
                        ? const Text('المساحة الحالية')
                        : (w.isMain ? const Text('المساحة الرئيسية') : null),
                leading:
                    w.id == activeId
                        ? IconChip(
                          Icons.check,
                          color: Tw.accentInk,
                          bg: Tw.accentSoft,
                        )
                        : IconChip(Icons.work_outline),
                onTap:
                    _busy || w.id == activeId
                        ? null
                        : () => _run(
                          () => host.switchTo(w.id, tab: AppTabs.settings),
                        ),
                trailing: IconButton(
                  tooltip: 'إجراءات «${w.name}»',
                  onPressed: _busy ? null : () => _menu(w, activeId),
                  icon: Icon(Icons.more_horiz, size: 24, color: Tw.ink2),
                ),
              ),
            ListRow(
              title: 'مساحة عمل جديدة',
              titleColor: Tw.accentInk,
              leading: IconChip(
                Icons.add,
                color: Tw.accentInk,
                bg: Tw.accentSoft,
              ),
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
