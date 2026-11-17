// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../app_services.dart';
import 'adjustments_page.dart';
import 'erp_theme.dart';
import 'erp_widgets.dart';
import 'payroll_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'sheet_page.dart';
import 'workspaces_card.dart';

/// Bottom navigation tabs.
abstract final class AppTabs {
  static const sheet = 0;
  static const payroll = 1;
  static const adjustments = 2;
  static const search = 3;
  static const settings = 4;
}

/// The frame of «المدقق»: a compact top bar (page title, workspace menu,
/// the page's main action) and the bottom navigation.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = 1});
  final int initialTab;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _NavItem {
  const _NavItem(this.icon, this.activeIcon, this.label, this.title);
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String title;
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int _index = widget.initialTab;
  final _periods = GlobalKey<SheetPageState>();
  final _audit = GlobalKey<PayrollPageState>();

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
    _NavItem(
      Icons.calendar_month_outlined,
      Icons.calendar_month,
      'الفترات',
      'فترات الرواتب',
    ),
    _NavItem(
      Icons.fact_check_outlined,
      Icons.fact_check,
      'التدقيق',
      'تدقيق الرواتب',
    ),
    _NavItem(
      Icons.balance_outlined,
      Icons.balance,
      'التسويات',
      'تسويات الرواتب',
    ),
    _NavItem(
      Icons.manage_search,
      Icons.manage_search,
      'الاستعلام',
      'الاستعلام',
    ),
    _NavItem(Icons.settings_outlined, Icons.settings, 'الإعدادات', 'الإعدادات'),
  ];

  void goTo(int index) => setState(() => _index = index);

  /// From the periods list: audit that period.
  void _auditPeriod(int cycleId) {
    goTo(AppTabs.payroll);
    _audit.currentState?.openCycle(cycleId);
  }

  // ------------------------------------------------------------ top bar

  Widget _topBar(BuildContext context) {
    final services = AppScope.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Tw.slate200)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _items[_index].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Tw.slate900,
                    ),
                  ),
                ),
                _workspaceMenu(context, services),
                if (_index == AppTabs.sheet) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'فترة رواتب جديدة',
                    child: InkResponse(
                      radius: 22,
                      onTap: () => _periods.currentState?.openCreate(),
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Tw.indigo600,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The open workspace (named only when there are several) and the menu
  /// to switch, add or manage workspaces (owner's request: from the top
  /// bar).
  Widget _workspaceMenu(BuildContext context, AppServices services) {
    final host = services.host;
    final activeId = services.workspace.id;
    final several = host.workspaces.length > 1;
    return PopupMenuButton<int>(
      tooltip: 'مساحات العمل',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 300),
      onSelected: (v) => _onWorkspaceMenu(context, v),
      itemBuilder:
          (_) => [
            const PopupMenuItem<int>(
              enabled: false,
              height: 30,
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
                height: 44,
                child: Row(
                  children: [
                    Icon(
                      w.id == activeId
                          ? Icons.check_circle
                          : Icons.work_outline,
                      size: 18,
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
                          color: w.id == activeId ? Tw.indigo700 : Tw.slate900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const PopupMenuDivider(height: 8),
            const PopupMenuItem<int>(
              value: _addWorkspace,
              height: 44,
              child: Row(
                children: [
                  Icon(Icons.add, size: 18, color: Tw.indigo600),
                  SizedBox(width: 10),
                  Text('مساحة عمل جديدة', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
            const PopupMenuItem<int>(
              value: _manageWorkspaces,
              height: 44,
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 18, color: Tw.slate500),
                  SizedBox(width: 10),
                  Text('إدارة مساحات العمل', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
      child: Container(
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        padding: EdgeInsets.symmetric(horizontal: several ? 10 : 8),
        decoration: BoxDecoration(
          color: Tw.slate50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Tw.slate200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.work_outline, size: 16, color: Tw.slate600),
            if (several) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  services.workspace.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Tw.slate700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 16, color: Tw.slate500),
          ],
        ),
      ),
    );
  }

  static const _addWorkspace = -1;
  static const _manageWorkspaces = -2;

  Future<void> _onWorkspaceMenu(BuildContext context, int value) async {
    final host = AppScope.read(context).host;
    if (value == _manageWorkspaces) {
      goTo(AppTabs.settings);
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

  // ------------------------------------------------------- bottom nav

  Widget _bottomNav() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Tw.slate200)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == _index,
                  button: true,
                  label: _items[i].label,
                  child: InkResponse(
                    onTap: () => goTo(i),
                    radius: 34,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 48,
                          height: 28,
                          decoration: BoxDecoration(
                            color:
                                i == _index ? Tw.indigo50 : Colors.transparent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Icon(
                            i == _index ? _items[i].activeIcon : _items[i].icon,
                            size: 21,
                            color: i == _index ? Tw.indigo600 : Tw.slate500,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _items[i].label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight:
                                  i == _index
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                              color: i == _index ? Tw.indigo700 : Tw.slate500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Tw.slate50,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _topBar(context),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          SheetPage(key: _periods, onAudit: _auditPeriod),
          PayrollPage(
            key: _audit,
            active: _index == AppTabs.payroll,
            onOpenSheet: () => goTo(AppTabs.sheet),
            onOpenSettings: () => goTo(AppTabs.settings),
          ),
          AdjustmentsPage(active: _index == AppTabs.adjustments),
          SearchPage(active: _index == AppTabs.search),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    ),
  );
}
