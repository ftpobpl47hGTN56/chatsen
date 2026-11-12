import '/Consts.dart';
import 'package:flutter/material.dart';
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
                darkTheme: ThemeManager.buildTheme(Brightness.dark, themeState.colorScheme, highContrast: themeState.highContrast, background: bg),
                theme: ThemeManager.buildTheme(Brightness.light, themeState.colorScheme, background: bg),
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
            return Center(child: CircularProgressIndicator.adaptive());
          },
        ),
      );
}
