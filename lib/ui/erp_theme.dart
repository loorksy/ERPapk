// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// The app palette ("Compact Fluid UI", 3.0). The names follow the
/// Tailwind scale the screens were written with; the values are the
/// restrained identity of «المدقق»: neutral greys, one accent (#5148DB)
/// and one success colour (#099C83).
abstract final class Tw {
  static const slate50 = Color(0xfff6f8fa); // background
  static const slate100 = Color(0xfff0f2f5);
  static const slate200 = Color(0xffe8ebf0); // borders
  static const slate300 = Color(0xffd3d8df);
  static const slate400 = Color(0xffa3abb6);
  static const slate500 = Color(0xff77818f); // secondary text
  static const slate600 = Color(0xff5c6674);
  static const slate700 = Color(0xff3c4652);
  static const slate800 = Color(0xff27303b);
  static const slate900 = Color(0xff18212b); // primary text

  static const indigo50 = Color(0xfff1f0fd);
  static const indigo100 = Color(0xffe5e3fb);
  static const indigo200 = Color(0xffcdc9f5);
  static const indigo500 = Color(0xff6b63e3);
  static const indigo600 = Color(0xff5148db); // accent
  static const indigo700 = Color(0xff433ac0);
  static const indigo800 = Color(0xff38309e);
  static const indigo900 = Color(0xff2d277d);

  static const violet500 = Color(0xff8b5cf6);

  static const emerald50 = Color(0xffe9f6f3);
  static const emerald200 = Color(0xffa8dfd5);
  static const emerald500 = Color(0xff12ad92);
  static const emerald600 = Color(0xff099c83); // success
  static const emerald700 = Color(0xff07826e);
  static const emerald800 = Color(0xff066859);
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
  static const emerald100 = Color(0xffd2efe9);
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
    scaffoldBackgroundColor: Tw.slate50,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.compact,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Tw.slate900,
      displayColor: Tw.slate900,
    ),
    dividerColor: Tw.slate200,
    dividerTheme: const DividerThemeData(
      color: Tw.slate200,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      hintStyle: const TextStyle(color: Tw.slate400, fontSize: 14),
      border: _border(Tw.slate200),
      enabledBorder: _border(Tw.slate200),
      focusedBorder: _border(Tw.indigo600, width: 1.5),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Tw.slate200),
      ),
      textStyle: const TextStyle(
        fontFamily: erpFont,
        fontSize: 14,
        color: Tw.slate900,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Tw.indigo600 : Tw.slate300,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Tw.indigo600,
        textStyle: const TextStyle(
          fontFamily: erpFont,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        minimumSize: const Size(44, 40),
      ),
    ),
  );
}

OutlineInputBorder _border(Color c, {double width = 1}) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(12),
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
