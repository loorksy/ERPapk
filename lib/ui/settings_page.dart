// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app_services.dart';
import '../version.dart';
import 'erp_theme.dart';
import 'columns_card.dart';
import 'erp_widgets.dart';
import 'ui_kit.dart';
import 'workspaces_card.dart';

/// Settings → Google Sheets connection (the account is linked on the phone).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  bool? _syncEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final enabled = await AppScope.read(context).syncWorker.isEnabled();
      if (mounted) setState(() => _syncEnabled = enabled);
    });
  }

  /// ERP `POST /sheets/toggle-sync`.
  Future<void> _toggleSync(bool _) async {
    final services = AppScope.read(context);
    if (!services.auth.isConnected) {
      showToast(context, 'يرجى إعداد Google Sheets أولاً', ToastType.error);
      return;
    }
    final next = !(_syncEnabled ?? false);
    await services.syncWorker.setEnabled(next);
    if (!mounted) return;
    setState(() => _syncEnabled = next);
    showToast(
      context,
      next ? 'تم تفعيل المزامنة' : 'تم إيقاف المزامنة',
      ToastType.success,
    );
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final ok = await AppScope.read(context).auth.connect();
      if (!mounted) return;
      showToast(
        context,
        ok ? 'تم ربط حساب Google' : 'لم يكتمل ربط حساب Google',
        ok ? ToastType.success : ToastType.warning,
      );
    } catch (e) {
      if (mounted) showToast(context, 'تعذر ربط Google: $e', ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await AppScope.read(context).auth.disconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(context, 'تم فصل حساب Google', ToastType.success);
  }

  Future<void> _openMapping() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ColumnsPage()));

  void _about() => showInfo(
    context,
    'المدقق تطبيق لتدقيق كشوف الرواتب على الهاتف: يطابق كل مستخدم برقمه بين بيانات المستخدمين وجدولي الإدارة والوكيل («سحب وكالة» و«سحب وكالة - راتبيين» و«سحب إدارة» و«غير موجود»)، ويحسب الراتب بعد الخصم، وينسخ السجلات إلى أوراق الوكالات ويلوّنها. يطبّق أيضًا تسويات الرواتب (الإضافات والخصومات) مع المقاصة.\n\nكل الحساب يتم على الهاتف، وتُحفظ الفترات وحالات التدقيق في قاعدة بيانات على الجهاز. بدون ربط Google يمكن التدقيق من ملفات Excel أو CSV وتصدير النتائج إلى Excel.\n\nالتطبيق أداة تدقيق ومطابقة تشغيلية، وليس تدقيقًا ماليًا معتمدًا أو فحص امتثال تنظيمي.\n\nالإصدار $appVersion',
    title: 'حول المدقق',
  );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final auth = services.auth;
    final connected = auth.isConnected;
    return ListView(
      padding: Ds.pagePadding,
      children: [
        const SectionLabel('الربط والمزامنة', icon: Icons.link),
        GroupList(
          children: [
            ListRow(
              title: 'Google Sheets',
              leading: const SizedBox(
                width: 32,
                child: Center(
                  child: FaIcon(
                    FontAwesomeIcons.google,
                    size: 18,
                    color: Tw.slate700,
                  ),
                ),
              ),
              subtitle: Row(
                children: [
                  ColorDot(connected ? Tw.emerald500 : Tw.slate300, size: 8),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      connected ? 'متصل · ${auth.email ?? ''}' : 'غير متصل',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: connected ? Tw.emerald700 : Tw.slate500,
                      ),
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _busy
                      ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                      : TextButton(
                        onPressed: connected ? _disconnect : _connect,
                        style: TextButton.styleFrom(
                          foregroundColor:
                              connected ? Tw.slate600 : Tw.indigo600,
                        ),
                        child: Text(connected ? 'فصل' : 'ربط'),
                      ),
                  const InfoTip(
                    'يتصل الهاتف بحساب Google مباشرة دون خادم. يُستخدم الحساب لقراءة جداول الإدارة والوكيل وبيانات المستخدمين، ولكتابة نتائج التدقيق (النسخ إلى أوراق الوكالات، الراتب والحالة، التلوين) وتسويات الرواتب. الحساب مشترك بين كل مساحات العمل.',
                    title: 'Google Sheets',
                  ),
                ],
              ),
            ),
            ListRow(
              title: 'المزامنة التلقائية',
              leading: const SizedBox(
                width: 32,
                child: Icon(Icons.sync, size: 21, color: Tw.slate600),
              ),
              subtitle: const Text('كل دقيقتين أثناء فتح التطبيق'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: _syncEnabled ?? false,
                      onChanged: _syncEnabled == null ? null : _toggleSync,
                    ),
                  ),
                  const InfoTip(
                    'كما في النظام: كل دقيقتين تُحدَّث لقطات الفترات المرتبطة بـ Google وحالة التدقيق اليدوي (السجلات الملوّنة) للاستعلام، أثناء فتح التطبيق.',
                    title: 'المزامنة التلقائية',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const WorkspacesCard(),
        const SizedBox(height: 12),
        const SectionLabel('البيانات', icon: Icons.view_column_outlined),
        GroupList(
          children: [
            ListRow(
              title: 'ربط حقول البيانات',
              leading: const SizedBox(
                width: 32,
                child: Icon(
                  Icons.view_column_outlined,
                  size: 21,
                  color: Tw.slate600,
                ),
              ),
              subtitle: const Text(
                'أعمدة الإدارة والوكيل وبيانات المستخدمين وغير المذكورين',
              ),
              trailing: const RowChevron(),
              onTap: _openMapping,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('التطبيق', icon: Icons.info_outline),
        GroupList(
          children: [
            ListRow(
              title: 'حول المدقق',
              leading: Image.asset(
                'assets/brand/logo.png',
                width: 32,
                height: 32,
              ),
              subtitle: const Text('الإصدار $appVersion'),
              trailing: const RowChevron(),
              onTap: _about,
            ),
          ],
        ),
      ],
    );
  }
}
