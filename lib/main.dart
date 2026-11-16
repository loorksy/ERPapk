// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_services.dart';
import 'ui/erp_theme.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AuditApplication());
}

class AuditApplication extends StatefulWidget {
  const AuditApplication({super.key});
  @override
  State<AuditApplication> createState() => _AuditApplicationState();
}

class _AuditApplicationState extends State<AuditApplication> {
  late final Future<AppServices> _services = AppServices.open();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'تدقيق لورك',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildErpTheme(),
    home: FutureBuilder<AppServices>(
      future: _services,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Scaffold(
            body: Center(child: Text('تعذر فتح البيانات المحفوظة على الجهاز.')),
          );
        }
        final services = snap.data;
        if (services == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return AppScope(services: services, child: const AppShell());
      },
    ),
  );
}
