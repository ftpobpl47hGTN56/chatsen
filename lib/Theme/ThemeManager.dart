import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ThemeManager {
  static Map<String, List<dynamic>> colors = {
    'red': [Colors.red, Colors.redAccent],
    'pink': [Colors.pink, Colors.pinkAccent],
    'purple': [Colors.purple, Colors.purpleAccent],
    'deepPurple': [Colors.deepPurple, Colors.deepPurpleAccent],
    'indigo': [Colors.indigo, Colors.indigoAccent],
    'blue': [Colors.blue, Colors.blueAccent],
    'lightBlue': [Colors.lightBlue, Colors.lightBlueAccent],
    'cyan': [Colors.cyan, Colors.cyanAccent],
    'teal': [Colors.teal, Colors.tealAccent],
    'green': [Colors.green, Colors.greenAccent],
    'lightGreen': [Colors.lightGreen, Colors.lightGreenAccent],
    'lime': [Colors.lime, Colors.limeAccent],
    'yellow': [Colors.yellow, Colors.yellowAccent],
    'amber': [Colors.amber, Colors.amberAccent],
    'orange': [Colors.orange, Colors.orangeAccent],
    'deepOrange': [Colors.deepOrange, Colors.deepOrangeAccent],
  };

  /// DearKing mod: готовые фоны. null = стандартная тема (системная яркость).
  static const List<Color?> backgrounds = [
    null, // стандарт
    Color(0xFF000000), // AMOLED
    Color(0xFF18181B), // графит (как Twitch)
    Color(0xFF0E1621), // ночной синий
    Color(0xFF171222), // тёмно-фиолетовый
    Color(0xFF0F1B15), // лесной
    Color(0xFF1E1712), // кофейный
    Color(0xFF221014), // винный
    Color(0xFFEFEFF1), // светло-серый
    Color(0xFFFFFFFF), // белый
    Color(0xFFF8BBD0), // розовый
    Color(0xFFBBDEFB), // синий
    Color(0xFFFFF59D), // жёлтый
  ];

  static Brightness brightnessOf(Color c) => c.computeLuminance() > 0.4 ? Brightness.light : Brightness.dark;

  static ThemeData buildTheme(Brightness brightness, String color,
      {bool highContrast = false, Color? background, bool accentBorders = false}) {
    if (background != null) brightness = brightnessOf(background);
    var baseColorScheme = brightness == Brightness.light
        ? ColorScheme.light()
        : ColorScheme.dark();
    // поверхность (карточки, шторки) — чуть светлее/темнее фона
    final customSurface = background == null
        ? null
        : Color.lerp(background, brightness == Brightness.dark ? Colors.white : Colors.black, 0.07);
    var colorScheme = ColorScheme.fromSwatch(
      primarySwatch: (colors[color] ?? colors['amber']!).first,
      brightness: brightness,
      backgroundColor: background ??
          (brightness == Brightness.dark
              ? (highContrast ? Colors.black : Colors.grey[900])
              : Colors.grey[100]),
    ).copyWith(
      surface: customSurface ??
          (brightness == Brightness.dark
              ? (highContrast ? Color.fromARGB(255, 16, 16, 16) : Colors.grey[850])
              : baseColorScheme.surface),
    );
    var themeData = ThemeData.from(colorScheme: colorScheme).copyWith(
      scaffoldBackgroundColor: colorScheme.background,
    );
    if (background != null) themeData = themeData.copyWith(canvasColor: background);
    if (accentBorders) themeData = _withAccentBorders(themeData);
    return themeData.copyWith(
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.primary,
      ),
      appBarTheme: AppBarTheme(
        iconTheme: IconThemeData(
          color: themeData.hintColor,
        ),
        shadowColor: Colors.black45,
        backgroundColor: colorScheme.surface,
        titleTextStyle: TextStyle(
          fontSize: 20.0,
          fontWeight: FontWeight.w500,
          color: themeData.hintColor,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 0.0, color: Colors.transparent),
        ),
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurface.withAlpha(192),
      ),
      // platform: TargetPlatform.iOS,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  static Widget routeWrapper({
    required BuildContext context,
    required Widget child,
  }) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarBrightness: Theme.of(context).brightness == Brightness.light
            ? Brightness.light
            : Brightness.dark,
        statusBarIconBrightness:
            Theme.of(context).brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
      ),
      child: child,
    );
  }

  /// DearKing mod: рамка 2px цвета акцента у кнопок, карточек, диалогов, шторок, чипов.
  static ThemeData _withAccentBorders(ThemeData t) {
    final side = BorderSide(color: t.colorScheme.primary, width: 2);
    RoundedRectangleBorder r(double radius) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);
    ButtonStyle btn(ButtonStyle? base) => (base ?? const ButtonStyle()).copyWith(
          side: WidgetStatePropertyAll(side),
          shape: WidgetStatePropertyAll(r(14)),
        );
    return t.copyWith(
      filledButtonTheme: FilledButtonThemeData(style: btn(t.filledButtonTheme.style)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: btn(t.outlinedButtonTheme.style)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: btn(t.elevatedButtonTheme.style)),
      textButtonTheme: TextButtonThemeData(style: btn(t.textButtonTheme.style)),
      segmentedButtonTheme: SegmentedButtonThemeData(style: (t.segmentedButtonTheme.style ?? const ButtonStyle()).copyWith(side: WidgetStatePropertyAll(side))),
      cardTheme: t.cardTheme.copyWith(shape: r(12)),
      dialogTheme: t.dialogTheme.copyWith(shape: r(20)),
      bottomSheetTheme: t.bottomSheetTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), side: side),
      ),
      popupMenuTheme: t.popupMenuTheme.copyWith(shape: r(12)),
      chipTheme: t.chipTheme.copyWith(side: side),
      snackBarTheme: t.snackBarTheme.copyWith(shape: r(12)),
    );
  }
}
