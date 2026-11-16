// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'erp_theme.dart';
import 'payroll_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'sheet_page.dart';

/// Mobile layout of the ERP dashboard: white top header with the page title
/// in indigo and the white bottom navigation bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _NavItem {
  const _NavItem(this.icon, this.label, this.title);
  final FaIconData icon;
  final String label;
  final String title;
}

class _AppShellState extends State<AppShell> {
  int _index = 1;

  static const _items = [
    _NavItem(FontAwesomeIcons.fileExcel, 'Sheet', 'Sheet'),
    _NavItem(FontAwesomeIcons.moneyCheckDollar, 'تدقيق راتب', 'تدقيق الرواتب'),
    _NavItem(FontAwesomeIcons.magnifyingGlass, 'البحث', 'البحث'),
    _NavItem(FontAwesomeIcons.gear, 'الإعدادات', 'الإعدادات'),
  ];

  void goTo(int index) => setState(() => _index = index);

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
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Tw.indigo500, Tw.indigo700],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const FaIcon(
                      FontAwesomeIcons.clipboardCheck,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _items[_index].title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Tw.indigo600,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
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
