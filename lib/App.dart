import '/Consts.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '/Components/UserPrefs.dart';
import '/Components/Backup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '/Components/Notification.dart';
import 'BackgroundAudio/BackgroundAudioWrapper.dart';
import 'Pages/Home.dart';
import 'Settings/Settings.dart';
import 'Settings/SettingsState.dart';
import 'Theme/ThemeBloc.dart';
import 'Theme/ThemeManager.dart';
import 'Theme/ThemeState.dart';

/// Our [App] class. It represents our MaterialApp and will redirect us to our app's homepage.
class App extends StatefulWidget {
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  Key globalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // после установки — предложить восстановить настройки; затем первое автосохранение
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 2));
      await Backup.maybeOfferRestore();
      await Future.delayed(const Duration(seconds: 8));
      await Backup.autoSave();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // приложение свернули — сохраняем копию настроек
    if (state == AppLifecycleState.paused) Backup.autoSave();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<Settings, SettingsState>(
        builder: (context, settingsState) => BlocBuilder<ThemeBloc, ThemeState>(
          builder: (context, themeState) {
            if (themeState is ThemeLoaded && settingsState is SettingsLoaded) {
              // DearKing mod: фон и язык из UserPrefs (меняются без перезапуска)
              return ValueListenableBuilder<int>(
                valueListenable: UserPrefs.instance.appearance,
                builder: (context, _, __) {
                final bg = UserPrefs.instance.background;
                return MaterialApp(
                navigatorKey: Backup.navigatorKey,
                darkTheme: ThemeManager.buildTheme(Brightness.dark, themeState.colorScheme, highContrast: themeState.highContrast, background: bg, accentBorders: UserPrefs.instance.accentBorders, accent: UserPrefs.instance.accent),
                theme: ThemeManager.buildTheme(Brightness.light, themeState.colorScheme, background: bg, accentBorders: UserPrefs.instance.accentBorders, accent: UserPrefs.instance.accent),
                // свой фон сам задаёт светлую/тёмную тему
                themeMode: bg != null ? (ThemeManager.brightnessOf(bg) == Brightness.light ? ThemeMode.light : ThemeMode.dark) : themeState.mode,
                locale: Locale(UserPrefs.instance.lang),
                supportedLocales: const [Locale('en'), Locale('ru')],
                // системные тексты Flutter (меню «Копировать/Вставить», диалоги) тоже на выбранном языке
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                debugShowCheckedModeBanner: false,
                home: NotificationWrapper(
                  child: Builder(
                    builder: (context) => ThemeManager.routeWrapper(
                      context: context,
                      child: settingsState.notificationBackground && !kPlayStoreRelease
                          ? BackgroundAudioWrapper(
                              child: HomePage(key: globalKey),
                            )
                          : HomePage(key: globalKey),
                    ),
                  ),
                ),
              );
                },
              );
            }
            // DearKing mod: вместо вечного спиннера — через 8 с экран с кнопкой сброса оформления
            return const _StartupWaiter();
          },
        ),
      );
}


/// Ожидание загрузки настроек. Если что-то пошло не так (например, испорченный импорт),
/// через 8 секунд предлагает сбросить настройки и тему — аккаунты и каналы не трогаются.
class _StartupWaiter extends StatefulWidget {
  const _StartupWaiter();

  @override
  State<_StartupWaiter> createState() => _StartupWaiterState();
}

class _StartupWaiterState extends State<_StartupWaiter> {
  bool slow = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => slow = true);
    });
  }

  Future<void> _reset() async {
    for (final name in ['Settings', 'Theme', 'ModSettings']) {
      try {
        final box = Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
        await box.clear();
      } catch (_) {}
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFF121212),
          child: Center(
            child: !slow
                ? const CircularProgressIndicator.adaptive()
                : Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr('Settings failed to load.', 'Не удалось загрузить настройки.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 18, decoration: TextDecoration.none),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr('Reset settings and theme? Accounts and channels are kept.', 'Сбросить настройки и тему? Аккаунты и каналы сохранятся.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14, decoration: TextDecoration.none),
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: _reset,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            decoration: BoxDecoration(color: const Color(0xFFE91E63), borderRadius: BorderRadius.circular(14)),
                            child: Text(
                              tr('Reset and close', 'Сбросить и закрыть'),
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
}
