// Flutter 3.50 deprecates its bundled Material exports; keep the SDK widgets.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// One set of colours of the app (light or dark). The names follow the
/// Tailwind scale the screens were written with.
class TwPalette {
  const TwPalette({
    required this.slate50,
    required this.slate100,
    required this.slate200,
    required this.slate300,
    required this.slate400,
    required this.slate500,
    required this.slate600,
    required this.slate700,
    required this.slate800,
    required this.slate900,
    required this.indigo50,
    required this.indigo100,
    required this.indigo200,
    required this.indigo500,
    required this.indigo600,
    required this.indigo700,
    required this.indigo800,
    required this.indigo900,
    required this.violet500,
    required this.emerald50,
    required this.emerald200,
    required this.emerald500,
    required this.emerald600,
    required this.emerald700,
    required this.emerald800,
    required this.teal500,
    required this.amber50,
    required this.amber100,
    required this.amber200,
    required this.amber500,
    required this.amber600,
    required this.amber700,
    required this.amber800,
    required this.amber900,
    required this.amber950,
    required this.orange500,
    required this.red50,
    required this.red100,
    required this.red600,
    required this.red700,
    required this.rose500,
    required this.pink500,
    required this.purple500,
    required this.yellow400,
    required this.sky50,
    required this.sky200,
    required this.sky300,
    required this.sky600,
    required this.sky700,
    required this.sky800,
    required this.emerald100,
    required this.red200,
    required this.amber300,
    required this.blue500,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.neutralSoft,
    required this.onAccent,
    required this.scrim,
  });
  final Color slate50;
  final Color slate100;
  final Color slate200;
  final Color slate300;
  final Color slate400;
  final Color slate500;
  final Color slate600;
  final Color slate700;
  final Color slate800;
  final Color slate900;
  final Color indigo50;
  final Color indigo100;
  final Color indigo200;
  final Color indigo500;
  final Color indigo600;
  final Color indigo700;
  final Color indigo800;
  final Color indigo900;
  final Color violet500;
  final Color emerald50;
  final Color emerald200;
  final Color emerald500;
  final Color emerald600;
  final Color emerald700;
  final Color emerald800;
  final Color teal500;
  final Color amber50;
  final Color amber100;
  final Color amber200;
  final Color amber500;
  final Color amber600;
  final Color amber700;
  final Color amber800;
  final Color amber900;
  final Color amber950;
  final Color orange500;
  final Color red50;
  final Color red100;
  final Color red600;
  final Color red700;
  final Color rose500;
  final Color pink500;
  final Color purple500;
  final Color yellow400;
  final Color sky50;
  final Color sky200;
  final Color sky300;
  final Color sky600;
  final Color sky700;
  final Color sky800;
  final Color emerald100;
  final Color red200;
  final Color amber300;
  final Color blue500;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color neutralSoft;
  final Color onAccent;
  final Color scrim;

  /// Light, from the owner's mockup (`docs/design/almudaqqiq-redesign.html`,
  /// `:root`): ledger paper, one green ink, sheet colours for data. The
  /// Tailwind names map onto the mockup tokens (slate → ink / rule,
  /// indigo + emerald → accent, amber → warn, red → danger, sky → info).
  static const light = TwPalette(
    slate50: Color(0xfff1f4f0), // --paper
    slate100: Color(0xfff2f5f1), // --surface-2
    slate200: Color(0xffe1e7e0), // --rule
    slate300: Color(0xffd3dbd2),
    slate400: Color(0xff98a39d), // --hatch
    slate500: Color(0xff6e7a74), // --ink-3
    slate600: Color(0xff56645d), // --ink-2
    slate700: Color(0xff3b4943),
    slate800: Color(0xff26332d),
    slate900: Color(0xff17231e), // --ink
    indigo50: Color(0xffe1eee7), // --accent-soft
    indigo100: Color(0xffd2e6db),
    indigo200: Color(0xffb5d5c5),
    indigo500: Color(0xff2b7c65),
    indigo600: Color(0xff1e6b56), // --accent
    indigo700: Color(0xff1a6450), // --accent-ink
    indigo800: Color(0xff175544), // --accent-press
    indigo900: Color(0xff103c30),
    violet500: Color(0xff8b5cf6),
    emerald50: Color(0xffe1eee7),
    emerald200: Color(0xffb5d5c5),
    emerald500: Color(0xff2b7c65),
    emerald600: Color(0xff1e6b56),
    emerald700: Color(0xff1a6450),
    emerald800: Color(0xff175544),
    teal500: Color(0xff14b8a6),
    amber50: Color(0xfff6ead2), // --warn-soft
    amber100: Color(0xfff1dfbd),
    amber200: Color(0xffe6cd9c),
    amber500: Color(0xffb27a1c),
    amber600: Color(0xff9c660c),
    amber700: Color(0xff8a5300), // --warn
    amber800: Color(0xff754600),
    amber900: Color(0xff5f3900),
    amber950: Color(0xff3f2600),
    orange500: Color(0xfff97316),
    red50: Color(0xfff7e2de), // --danger-soft
    red100: Color(0xfff1d2cc),
    red600: Color(0xffa3352a), // --danger
    red700: Color(0xff8c2b21),
    rose500: Color(0xfff43f5e),
    pink500: Color(0xffec4899),
    purple500: Color(0xffa855f7),
    yellow400: Color(0xfffacc15),
    sky50: Color(0xffe2ebf3), // --info-soft
    sky200: Color(0xffc3d5e6),
    sky300: Color(0xff9bb8d2),
    sky600: Color(0xff285a80), // --info
    sky700: Color(0xff224e70),
    sky800: Color(0xff1c415e),
    emerald100: Color(0xffd2e6db),
    red200: Color(0xffe8b7ae),
    amber300: Color(0xffd9b26e),
    blue500: Color(0xff3b82f6),
    surface: Color(0xffffffff), // --surface
    surface2: Color(0xfff2f5f1), // --surface-2
    surface3: Color(0xffe6ebe5), // --surface-3
    neutralSoft: Color(0xffe7ece6), // --neutral-soft
    onAccent: Color(0xffffffff), // --on-accent
    scrim: Color(0x6b0e1612), // --scrim
  );

  /// Dark, from the mockup's `:root[data-theme="dark"]`.
  static const dark = TwPalette(
    slate50: Color(0xff101613), // --paper
    slate100: Color(0xff202a25), // --surface-2
    slate200: Color(0xff28332e), // --rule
    slate300: Color(0xff36433c),
    slate400: Color(0xff6e7b74), // --hatch
    slate500: Color(0xff7d8a83), // --ink-3
    slate600: Color(0xffa3b0a9), // --ink-2
    slate700: Color(0xffbfcac4),
    slate800: Color(0xffd2dbd6),
    slate900: Color(0xffe2e9e5), // --ink
    indigo50: Color(0xff1c362d), // --accent-soft
    indigo100: Color(0xff234437),
    indigo200: Color(0xff2f5a49),
    indigo500: Color(0xff6cc6a5),
    indigo600: Color(0xff5dbe9b), // --accent
    indigo700: Color(0xff86d4b8), // --accent-ink
    indigo800: Color(0xff4faa89), // --accent-press
    indigo900: Color(0xffc0eadb),
    violet500: Color(0xff8b5cf6),
    emerald50: Color(0xff1c362d),
    emerald200: Color(0xff2f5a49),
    emerald500: Color(0xff6cc6a5),
    emerald600: Color(0xff5dbe9b),
    emerald700: Color(0xff86d4b8),
    emerald800: Color(0xffa3e0ca),
    teal500: Color(0xff2dd4bf),
    amber50: Color(0xff382d18), // --warn-soft
    amber100: Color(0xff43361d),
    amber200: Color(0xff5b4826),
    amber500: Color(0xffd9a24a),
    amber600: Color(0xffdfab57),
    amber700: Color(0xffe5b465), // --warn
    amber800: Color(0xffebc583),
    amber900: Color(0xfff0d4a2),
    amber950: Color(0xfff5e3c2),
    orange500: Color(0xfffb8a3c),
    red50: Color(0xff3a211d), // --danger-soft
    red100: Color(0xff472822),
    red600: Color(0xffee9c8e), // --danger
    red700: Color(0xfff2b3a8),
    rose500: Color(0xfffb7185),
    pink500: Color(0xfff472b6),
    purple500: Color(0xffc084fc),
    yellow400: Color(0xfffacc15),
    sky50: Color(0xff1c2935), // --info-soft
    sky200: Color(0xff24384a),
    sky300: Color(0xff2f4c63),
    sky600: Color(0xff97bce0), // --info
    sky700: Color(0xffb0cde8),
    sky800: Color(0xffc8ddf0),
    emerald100: Color(0xff234437),
    red200: Color(0xff5e332b),
    amber300: Color(0xff7a5f2c),
    blue500: Color(0xff60a5fa),
    surface: Color(0xff18201c), // --surface
    surface2: Color(0xff202a25), // --surface-2
    surface3: Color(0xff2b3631), // --surface-3
    neutralSoft: Color(0xff26302b), // --neutral-soft
    onAccent: Color(0xff0b1712), // --on-accent
    scrim: Color(0x94000000), // --scrim
  );
}

/// The app palette. Every screen reads its colours here; switching
/// [palette] (Settings ← المظهر) and rebuilding the app changes the
/// whole interface between light and dark.
abstract final class Tw {
  static TwPalette palette = TwPalette.light;
  static bool get isDark => identical(palette, TwPalette.dark);

  static Color get slate50 => palette.slate50;
  static Color get slate100 => palette.slate100;
  static Color get slate200 => palette.slate200;
  static Color get slate300 => palette.slate300;
  static Color get slate400 => palette.slate400;
  static Color get slate500 => palette.slate500;
  static Color get slate600 => palette.slate600;
  static Color get slate700 => palette.slate700;
  static Color get slate800 => palette.slate800;
  static Color get slate900 => palette.slate900;
  static Color get indigo50 => palette.indigo50;
  static Color get indigo100 => palette.indigo100;
  static Color get indigo200 => palette.indigo200;
  static Color get indigo500 => palette.indigo500;
  static Color get indigo600 => palette.indigo600;
  static Color get indigo700 => palette.indigo700;
  static Color get indigo800 => palette.indigo800;
  static Color get indigo900 => palette.indigo900;
  static Color get violet500 => palette.violet500;
  static Color get emerald50 => palette.emerald50;
  static Color get emerald200 => palette.emerald200;
  static Color get emerald500 => palette.emerald500;
  static Color get emerald600 => palette.emerald600;
  static Color get emerald700 => palette.emerald700;
  static Color get emerald800 => palette.emerald800;
  static Color get teal500 => palette.teal500;
  static Color get amber50 => palette.amber50;
  static Color get amber100 => palette.amber100;
  static Color get amber200 => palette.amber200;
  static Color get amber500 => palette.amber500;
  static Color get amber600 => palette.amber600;
  static Color get amber700 => palette.amber700;
  static Color get amber800 => palette.amber800;
  static Color get amber900 => palette.amber900;
  static Color get amber950 => palette.amber950;
  static Color get orange500 => palette.orange500;
  static Color get red50 => palette.red50;
  static Color get red100 => palette.red100;
  static Color get red600 => palette.red600;
  static Color get red700 => palette.red700;
  static Color get rose500 => palette.rose500;
  static Color get pink500 => palette.pink500;
  static Color get purple500 => palette.purple500;
  static Color get yellow400 => palette.yellow400;
  static Color get sky50 => palette.sky50;
  static Color get sky200 => palette.sky200;
  static Color get sky300 => palette.sky300;
  static Color get sky600 => palette.sky600;
  static Color get sky700 => palette.sky700;
  static Color get sky800 => palette.sky800;
  static Color get emerald100 => palette.emerald100;
  static Color get red200 => palette.red200;
  static Color get amber300 => palette.amber300;
  static Color get blue500 => palette.blue500;
  static Color get surface => palette.surface;
  static Color get surface2 => palette.surface2;
  static Color get scrim => palette.scrim;
  static Color get surface3 => palette.surface3;
  static Color get neutralSoft => palette.neutralSoft;
  static Color get onAccent => palette.onAccent;

  // The mockup's token names, for new code.
  static Color get paper => palette.slate50;
  static Color get ink => palette.slate900;
  static Color get ink2 => palette.slate600;
  static Color get ink3 => palette.slate500;
  static Color get rule => palette.slate200;
  static Color get hatch => palette.slate400;
  static Color get accent => palette.indigo600;
  static Color get accentPress => palette.indigo800;
  static Color get accentSoft => palette.indigo50;
  static Color get accentInk => palette.indigo700;
  static Color get warn => palette.amber700;
  static Color get warnSoft => palette.amber50;
  static Color get info => palette.sky600;
  static Color get infoSoft => palette.sky50;
  static Color get danger => palette.red600;
  static Color get dangerSoft => palette.red50;
}

const String erpFont = 'Tajawal';

ThemeData buildErpTheme() {
  final brightness = Tw.isDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: Tw.accent,
    primary: Tw.accent,
    onPrimary: Tw.onAccent,
    secondaryContainer: Tw.accentSoft,
    onSecondaryContainer: Tw.accentInk,
    surface: Tw.surface,
    onSurface: Tw.ink,
    error: Tw.danger,
    brightness: brightness,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: erpFont,
    scaffoldBackgroundColor: Tw.paper,
    splashFactory: InkRipple.splashFactory,
  );
  // Body text of the mockup: Tajawal 500, 15 px.
  final text = base.textTheme
      .apply(bodyColor: Tw.ink, displayColor: Tw.ink)
      .copyWith(
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Tw.ink,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Tw.ink,
        ),
      );
  return base.copyWith(
    canvasColor: Tw.surface,
    cardColor: Tw.surface,
    textTheme: text,
    dividerColor: Tw.rule,
    dividerTheme: DividerThemeData(color: Tw.rule, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: Tw.ink2),
    // `.input`: 50 px, 13 px corners, surface-2 fill, accent border on focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tw.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: Tw.ink3, fontSize: 15),
      border: _border(Colors.transparent),
      enabledBorder: _border(Colors.transparent),
      disabledBorder: _border(Colors.transparent),
      focusedBorder: _border(Tw.accent, width: 1.5),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // `.dialog`: 26 px corners.
    dialogTheme: DialogThemeData(
      backgroundColor: Tw.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: Tw.scrim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titleTextStyle: TextStyle(
        fontFamily: erpFont,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: Tw.ink,
      ),
      contentTextStyle: TextStyle(
        fontFamily: erpFont,
        fontSize: 15,
        height: 1.75,
        color: Tw.ink2,
      ),
    ),
    // `.sheet`: 28 px top corners.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Tw.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Tw.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Tw.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: TextStyle(fontFamily: erpFont, fontSize: 15, color: Tw.ink),
    ),
    // `.switch`: accent track when on, surface-3 when off, light knob.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected)
                ? Colors.white
                : (Tw.isDark ? const Color(0xffe2e9e5) : Colors.white),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Tw.accent : Tw.surface3,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    // `.link` / `.btn-quiet`.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Tw.accentInk,
        textStyle: const TextStyle(
          fontFamily: erpFont,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
        minimumSize: const Size(44, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: Tw.accent,
      linearTrackColor: Tw.surface3,
      circularTrackColor: Colors.transparent,
    ),
    // `.nav`: 70 px, surface, a 58×30 accent-soft pill on the current tab.
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: Tw.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Tw.accentSoft,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: erpFont,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: s.contains(WidgetState.selected) ? Tw.accentInk : Tw.ink3,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected) ? Tw.accentInk : Tw.ink3,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Tw.accent,
      foregroundColor: Tw.onAccent,
      elevation: 4,
      highlightElevation: 6,
      extendedTextStyle: const TextStyle(
        fontFamily: erpFont,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

OutlineInputBorder _border(Color c, {double width = 1.5}) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(13),
  borderSide: BorderSide(color: c, width: width),
);

Color hexColor(String hex, [Color? fallback]) {
  fallback ??= Tw.slate400;
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
