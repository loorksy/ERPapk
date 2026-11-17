// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// Tailwind colors used by the LorkERP web interface.
abstract final class Tw {
  static const slate50 = Color(0xfff8fafc);
  static const slate100 = Color(0xfff1f5f9);
  static const slate200 = Color(0xffe2e8f0);
  static const slate300 = Color(0xffcbd5e1);
  static const slate400 = Color(0xff94a3b8);
  static const slate500 = Color(0xff64748b);
  static const slate600 = Color(0xff475569);
  static const slate700 = Color(0xff334155);
  static const slate800 = Color(0xff1e293b);
  static const slate900 = Color(0xff0f172a);

  static const indigo50 = Color(0xffeef2ff);
  static const indigo100 = Color(0xffe0e7ff);
  static const indigo200 = Color(0xffc7d2fe);
  static const indigo500 = Color(0xff6366f1);
  static const indigo600 = Color(0xff4f46e5);
  static const indigo700 = Color(0xff4338ca);
  static const indigo800 = Color(0xff3730a3);
  static const indigo900 = Color(0xff312e81);

  static const violet500 = Color(0xff8b5cf6);

  static const emerald50 = Color(0xffecfdf5);
  static const emerald200 = Color(0xffa7f3d0);
  static const emerald500 = Color(0xff10b981);
  static const emerald600 = Color(0xff059669);
  static const emerald700 = Color(0xff047857);
  static const emerald800 = Color(0xff065f46);
  static const teal500 = Color(0xff14b8a6);

  static const amber50 = Color(0xfffffbeb);
  static const amber100 = Color(0xfffef3c7);
  static const amber200 = Color(0xfffde68a);
  static const amber500 = Color(0xfff59e0b);
  static const amber600 = Color(0xffd97706);
  static const amber700 = Color(0xffb45309);
  static const amber800 = Color(0xff92400e);
  static const amber900 = Color(0xff78350f);
  static const amber950 = Color(0xff451a03);
  static const orange500 = Color(0xfff97316);

  static const red50 = Color(0xfffef2f2);
  static const red100 = Color(0xfffee2e2);
  static const red600 = Color(0xffdc2626);
  static const red700 = Color(0xffb91c1c);
  static const rose500 = Color(0xfff43f5e);
  static const pink500 = Color(0xffec4899);
  static const purple500 = Color(0xffa855f7);
  static const yellow400 = Color(0xfffacc15);
  // Sky (ERP «إضافات وخصومات» results).
  static const sky50 = Color(0xfff0f9ff);
  static const sky200 = Color(0xffbae6fd);
  static const sky300 = Color(0xff7dd3fc);
  static const sky600 = Color(0xff0284c7);
  static const sky700 = Color(0xff0369a1);
  static const sky800 = Color(0xff075985);
  static const emerald100 = Color(0xffd1fae5);
  static const red200 = Color(0xfffecaca);
  static const amber300 = Color(0xfffcd34d);
  static const blue500 = Color(0xff3b82f6);
}

const String erpFont = 'Tajawal';

ThemeData buildErpTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Tw.indigo600,
    primary: Tw.indigo600,
    surface: Colors.white,
    brightness: Brightness.light,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: erpFont,
    scaffoldBackgroundColor: Tw.slate100,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Tw.slate800,
      displayColor: Tw.slate900,
    ),
    dividerColor: Tw.slate200,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: const TextStyle(color: Tw.slate400, fontSize: 14),
      border: _border(Tw.slate300),
      enabledBorder: _border(Tw.slate300),
      focusedBorder: _border(Tw.indigo500, width: 2),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
    ),
  );
}

OutlineInputBorder _border(Color c, {double width = 1}) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(8),
  borderSide: BorderSide(color: c, width: width),
);

Color hexColor(String hex, [Color fallback = Tw.slate400]) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xff000000 | v);
}

String colorHex(Color c) {
  final v = c.toARGB32() & 0xffffff;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}
