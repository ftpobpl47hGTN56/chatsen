import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

/// Локальные настройки по пользователям: игнор и переименования.
/// Хранятся в Hive-боксах 'IgnoredUsers' (login -> true) и 'UserAliases' (login -> имя).
/// Это ChangeNotifier: чат подписан на него и перерисовывается при изменениях.
class UserPrefs extends ChangeNotifier {
  UserPrefs._();
  static final UserPrefs instance = UserPrefs._();

  Box? _ignored;
  Box? _aliases;

  /// id сообщений игнорируемых юзеров, которые пользователь раскрыл тапом.
  final Set<String> revealed = {};

  Future<void> init() async {
    _ignored = await Hive.openBox('IgnoredUsers');
    _aliases = await Hive.openBox('UserAliases');
  }

  String _k(String login) => login.toLowerCase();

  bool isIgnored(String? login) => login != null && (_ignored?.get(_k(login)) == true);

  Future<void> setIgnored(String login, bool value) async {
    if (value) {
      await _ignored?.put(_k(login), true);
    } else {
      await _ignored?.delete(_k(login));
    }
    notifyListeners();
  }

  List<String> get ignoredUsers => List<String>.from(_ignored?.keys ?? const []);

  String? aliasOf(String? login) => login == null ? null : _aliases?.get(_k(login)) as String?;

  Future<void> setAlias(String login, String? alias) async {
    final a = alias?.trim();
    if (a == null || a.isEmpty) {
      await _aliases?.delete(_k(login));
    } else {
      await _aliases?.put(_k(login), a);
    }
    notifyListeners();
  }

  void toggleRevealed(String? messageId) {
    if (messageId == null) return;
    if (!revealed.remove(messageId)) revealed.add(messageId);
    notifyListeners();
  }
}

/// Шторка снизу для приложения, которое живёт в immersive-режиме.
/// Открытие модалки на Android возвращает системный навбар (тот самый белый
/// полупрозрачный), поэтому прячем его обратно сразу после открытия и после закрытия.
Future<T?> showChatsenSheet<T>(BuildContext context, WidgetBuilder builder) async {
  void hideBars() {
    if (!kIsWeb && Platform.isAndroid) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  final future = showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _ImmersiveGuard(
      onShow: hideBars,
      child: Padding(
        // запас снизу, если навбар всё-таки показан свайпом — кнопки не уедут под него
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewPadding.bottom + MediaQuery.of(ctx).viewInsets.bottom),
        child: builder(ctx),
      ),
    ),
  );
  final result = await future;
  hideBars();
  return result;
}

class _ImmersiveGuard extends StatefulWidget {
  final VoidCallback onShow;
  final Widget child;
  const _ImmersiveGuard({required this.onShow, required this.child});

  @override
  State<_ImmersiveGuard> createState() => _ImmersiveGuardState();
}

class _ImmersiveGuardState extends State<_ImmersiveGuard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onShow());
    // второй раз — после анимации появления, Android иногда показывает бары с задержкой
    Future.delayed(const Duration(milliseconds: 350), widget.onShow);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
