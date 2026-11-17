// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app_services.dart';
import 'erp_theme.dart';
import 'columns_card.dart';
import 'erp_widgets.dart';
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const PageHeading(
          icon: FontAwesomeIcons.gear,
          title: 'الإعدادات',
          subtitle: 'ربط Google Sheets وبيانات التطبيق على هذا الجهاز',
        ),
        const SizedBox(height: 24),
        ErpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [Tw.slate50, Colors.white],
                  ),
                  border: Border(bottom: BorderSide(color: Tw.slate100)),
                ),
                child: const Row(
                  children: [
                    FaIcon(
                      FontAwesomeIcons.table,
                      size: 13,
                      color: Tw.emerald600,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Google Sheets',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Tw.slate800,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
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
                            connected
                                ? 'متصل: ${auth.email ?? ''}'
                                : 'غير متصل',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: connected ? Tw.emerald700 : Tw.slate600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'يتصل الهاتف بحساب Google مباشرة دون خادم. يُستخدم الحساب لقراءة جداول الإدارة والوكيل ومعلومات المستخدمين، ولكتابة نتائج التدقيق (نسخ الصفوف إلى أوراق الوجهة، عمود الراتب والحالة، وتلوين الصفوف) كما يفعل النظام.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Tw.slate600,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 16),
                    connected
                        ? ErpButton(
                          label: 'فصل الحساب',
                          icon: FontAwesomeIcons.linkSlash,
                          kind: ErpButtonKind.outline,
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
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1, color: Tw.slate100),
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'المزامنة التلقائية للدورات',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Tw.slate800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'كما في النظام: كل دقيقتين تُحدَّث لقطات الدورات المرتبطة بـ Google وحالة التدقيق اليدوي (الصفوف الملوّنة) للبحث، أثناء فتح التطبيق.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Tw.slate500,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        const WorkspacesCard(),
        const SizedBox(height: 16),
        const ColumnsCard(),
        const SizedBox(height: 16),
        ErpCard(
          padding: const EdgeInsets.all(16),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FaIcon(
                    FontAwesomeIcons.mobileScreen,
                    size: 13,
                    color: Tw.indigo600,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'التدقيق على الهاتف',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Tw.slate800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'منطق التدقيق هو نفسه في النظام: المطابقة برقم المستخدم، «سحب وكالة» و«سحب وكالة - راتبيين» و«سحب إدارة» و«غير موجود»، الراتب بعد الخصم، والألوان. كل الحساب يتم على الهاتف وتُحفظ الدورات وحالات التدقيق في قاعدة بيانات على الجهاز.\n\nبدون ربط Google يمكن التدقيق من ملفات Excel أو CSV وتصدير النتائج إلى ملف Excel.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Tw.slate600,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
