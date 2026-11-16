// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_services.dart';
import 'background/audit_worker.dart';
import 'ui/erp_theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAuditWorker();
  runApp(const AuditApplication());
}

class AuditApplication extends StatefulWidget {
  const AuditApplication({super.key});
  @override
  State<AuditApplication> createState() => _AuditApplicationState();
}

class _AuditApplicationState extends State<AuditApplication> {
  late final Future<AppServices> _services = AppServices.open();

  MaterialApp _app(Widget home) => MaterialApp(
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
    home: home,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<AppServices>(
    future: _services,
    builder: (context, snap) {
      if (snap.hasError) {
        return _app(
          const Scaffold(
            body: Center(child: Text('تعذر فتح البيانات المحفوظة على الجهاز.')),
          ),
        );
      }
      final services = snap.data;
      if (services == null) {
        return _app(
          const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      // AppScope sits above the Navigator so dialogs and bottom sheets
      // (new routes) can reach the database and the Google connection too.
      return AppScope(services: services, child: _app(const AppShell()));
    },
  );
}
