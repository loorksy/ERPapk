// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
      icon: FontAwesomeIcons.trashCan,
      iconColor: Tw.red600,
      iconBg: Tw.red100,
      title: 'حذف مساحة العمل',
      body:
          'سيُحذف من هذا الهاتف كل ما في «${w.name}»: الدورات وحالات التدقيق والإعدادات والأعمدة. لا يُحذف أي شيء من Google. لا يمكن التراجع.',
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
    return Panel(
      title: 'مساحات العمل',
      icon: FontAwesomeIcons.briefcase,
      info:
          'لكل مساحة عمل دوراتها وتدقيقها وإعداداتها وأعمدتها، منفصلة تمامًا عن غيرها (مثلًا شركة ثانية). حساب Google مشترك بين كل المساحات. التنقل بينها من القائمة في البار العلوي.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final w in host.workspaces)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: w.id == activeId ? Tw.indigo50 : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: w.id == activeId ? Tw.indigo200 : Tw.slate200,
                      ),
                    ),
                    child: Row(
                      children: [
                        FaIcon(
                          w.id == activeId
                              ? FontAwesomeIcons.solidCircleCheck
                              : FontAwesomeIcons.briefcase,
                          size: 14,
                          color: w.id == activeId ? Tw.indigo600 : Tw.slate400,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                w.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Tw.slate800,
                                ),
                              ),
                              if (w.id == activeId)
                                const Text(
                                  'مفتوحة الآن',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Tw.indigo600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (w.id != activeId)
                          TextButton(
                            onPressed:
                                _busy
                                    ? null
                                    : () => _run(
                                      () => host.switchTo(
                                        w.id,
                                        tab: AppTabs.settings,
                                      ),
                                    ),
                            child: const Text('فتح'),
                          ),
                        PopupMenuButton<String>(
                          enabled: !_busy,
                          icon: const FaIcon(
                            FontAwesomeIcons.ellipsisVertical,
                            size: 14,
                            color: Tw.slate500,
                          ),
                          onSelected: (v) {
                            if (v == 'rename') _rename(w);
                            if (v == 'delete') _delete(w);
                          },
                          itemBuilder:
                              (_) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('إعادة تسمية'),
                                ),
                                if (!w.isMain && w.id != activeId)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'حذف',
                                      style: TextStyle(color: Tw.red600),
                                    ),
                                  ),
                              ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                ErpButton(
                  label: 'إضافة مساحة عمل',
                  icon: FontAwesomeIcons.plus,
                  kind: ErpButtonKind.outline,
                  height: 42,
                  loading: _busy,
                  onPressed: _add,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
