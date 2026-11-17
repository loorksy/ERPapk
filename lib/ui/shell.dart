// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app_services.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'payroll_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'sheet_page.dart';
import 'workspaces_card.dart';

/// Mobile layout of the ERP dashboard: white top header with the page title
/// in indigo and the white bottom navigation bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = 1});
  final int initialTab;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _NavItem {
  const _NavItem(this.icon, this.label, this.title);
  final FaIconData icon;
  final String label;
  final String title;
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int _index = widget.initialTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.read(context);
      services.resumeAuditJobs();
      services.resumeBackgroundSync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final services = AppScope.read(context);
    if (state == AppLifecycleState.resumed) {
      services.resumeAuditJobs();
      services.resumeBackgroundSync();
    } else if (state == AppLifecycleState.paused) {
      services.syncWorker.stop();
    }
  }

  static const _items = [
    _NavItem(FontAwesomeIcons.fileExcel, 'Sheet', 'Sheet'),
    _NavItem(FontAwesomeIcons.moneyCheckDollar, 'تدقيق راتب', 'تدقيق الرواتب'),
    _NavItem(FontAwesomeIcons.magnifyingGlass, 'البحث', 'البحث'),
    _NavItem(FontAwesomeIcons.gear, 'الإعدادات', 'الإعدادات'),
  ];

  void goTo(int index) => setState(() => _index = index);

  /// Page title, and under it the open workspace: tapping it drops the
  /// workspace menu down from the top bar (owner's request, 2026-11-17).
  Widget _title(BuildContext context) {
    final services = AppScope.of(context);
    final host = services.host;
    final activeId = services.workspace.id;
    return PopupMenuButton<int>(
      tooltip: 'مساحات العمل',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      onSelected: (v) => _onWorkspaceMenu(context, v),
      itemBuilder:
          (_) => [
            const PopupMenuItem<int>(
              enabled: false,
              height: 32,
              child: Text(
                'مساحات العمل',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Tw.slate500,
                ),
              ),
            ),
            for (final w in host.workspaces)
              PopupMenuItem<int>(
                value: w.id,
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
                      child: Text(
                        w.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              w.id == activeId
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                          color: w.id == activeId ? Tw.indigo700 : Tw.slate800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem<int>(
              value: _addWorkspace,
              child: Row(
                children: [
                  FaIcon(FontAwesomeIcons.plus, size: 13, color: Tw.indigo600),
                  SizedBox(width: 10),
                  Text(
                    'إضافة مساحة عمل',
                    style: TextStyle(fontSize: 14, color: Tw.indigo700),
                  ),
                ],
              ),
            ),
            const PopupMenuItem<int>(
              value: _manageWorkspaces,
              child: Row(
                children: [
                  FaIcon(FontAwesomeIcons.gear, size: 13, color: Tw.slate500),
                  SizedBox(width: 10),
                  Text(
                    'إدارة مساحات العمل',
                    style: TextStyle(fontSize: 14, color: Tw.slate700),
                  ),
                ],
              ),
            ),
          ],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _items[_index].title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Tw.indigo600,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: Tw.slate100,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FaIcon(
                  FontAwesomeIcons.briefcase,
                  size: 10,
                  color: Tw.slate500,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    services.workspace.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Tw.slate600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const FaIcon(
                  FontAwesomeIcons.chevronDown,
                  size: 8,
                  color: Tw.slate500,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _addWorkspace = -1;
  static const _manageWorkspaces = -2;

  Future<void> _onWorkspaceMenu(BuildContext context, int value) async {
    final host = AppScope.read(context).host;
    if (value == _manageWorkspaces) {
      goTo(3);
      return;
    }
    if (value == _addWorkspace) {
      final name = await askWorkspaceName(context, 'مساحة عمل جديدة');
      if (name == null || name.trim().isEmpty || !mounted) return;
      try {
        final w = await host.create(name);
        await host.switchTo(w.id, tab: _index);
      } catch (e) {
        if (context.mounted) {
          showToast(
            context,
            e is ArgumentError ? '${e.message}' : '$e',
            ToastType.error,
          );
        }
      }
      return;
    }
    await host.switchTo(value, tab: _index);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Tw.slate100,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Tw.slate200)),
            boxShadow: [
              BoxShadow(
                color: Color(0x0a0f172a),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  // App logo (docs/brand).
                  Image.asset(
                    'assets/brand/logo.png',
                    width: 38,
                    height: 38,
                    filterQuality: FilterQuality.medium,
                  ),
                  Expanded(child: _title(context)),
                  const SizedBox(width: 52),
                ],
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const SheetPage(),
          PayrollPage(
            active: _index == 1,
            onOpenSheet: () => goTo(0),
            onOpenSettings: () => goTo(3),
          ),
          SearchPage(active: _index == 2),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Tw.slate200)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0d000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => goTo(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FaIcon(
                            _items[i].icon,
                            size: 18,
                            color: i == _index ? Tw.indigo600 : Tw.slate400,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _items[i].label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: i == _index ? Tw.indigo600 : Tw.slate400,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
