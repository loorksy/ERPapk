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

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    final connected = auth.isConnected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Panel(
          title: 'Google Sheets',
          icon: FontAwesomeIcons.google,
          iconColor: Tw.emerald600,
          iconBg: Tw.emerald50,
          info:
              'يتصل الهاتف بحساب Google مباشرة دون خادم. يُستخدم الحساب لقراءة جداول الإدارة والوكيل ومعلومات المستخدمين، ولكتابة نتائج التدقيق (نسخ الصفوف إلى أوراق الوجهة، عمود الراتب والحالة، وتلوين الصفوف) والإضافات والخصومات. الحساب مشترك بين كل مساحات العمل.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: connected ? Tw.emerald500 : Tw.slate300,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      connected ? 'متصل: ${auth.email ?? ''}' : 'غير متصل',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: connected ? Tw.emerald700 : Tw.slate600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              connected
                  ? ErpButton(
                    label: 'فصل الحساب',
                    icon: FontAwesomeIcons.linkSlash,
                    kind: ErpButtonKind.outline,
                    height: 42,
                    loading: _busy,
                    onPressed: _disconnect,
                  )
                  : ErpButton(
                    label: 'ربط حساب Google',
                    icon: FontAwesomeIcons.google,
                    kind: ErpButtonKind.indigo,
                    loading: _busy,
                    loadingLabel: 'جاري الربط...',
                    onPressed: _connect,
                  ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Tw.slate100),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'المزامنة التلقائية للدورات',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Tw.slate800,
                      ),
                    ),
                  ),
                  const InfoTip(
                    'كما في النظام: كل دقيقتين تُحدَّث لقطات الدورات المرتبطة بـ Google وحالة التدقيق اليدوي (الصفوف الملوّنة) للبحث، أثناء فتح التطبيق.',
                    title: 'المزامنة التلقائية',
                  ),
                  Switch(
                    value: _syncEnabled ?? false,
                    activeTrackColor: Tw.indigo600,
                    onChanged: _syncEnabled == null ? null : _toggleSync,
                  ),
                ],
              ),
            ],
          ),
        ),
        gap,
        const WorkspacesCard(),
        gap,
        const ColumnsCard(),
        gap,
        Panel(
          child: Row(
            children: [
              Image.asset('assets/brand/logo.png', width: 40, height: 40),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تدقيق لورك',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Tw.slate800,
                      ),
                    ),
                    Text(
                      'الإصدار $appVersion',
                      style: TextStyle(fontSize: 12, color: Tw.slate500),
                    ),
                  ],
                ),
              ),
              const InfoTip(
                'منطق التدقيق هو نفسه في النظام: المطابقة برقم المستخدم، «سحب وكالة» و«سحب وكالة - راتبيين» و«سحب إدارة» و«غير موجود»، الراتب بعد الخصم، والألوان. كل الحساب يتم على الهاتف وتُحفظ الدورات وحالات التدقيق في قاعدة بيانات على الجهاز.\n\nبدون ربط Google يمكن التدقيق من ملفات Excel أو CSV وتصدير النتائج إلى ملف Excel.',
                title: 'التدقيق على الهاتف',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
