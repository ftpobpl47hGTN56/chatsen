import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;

/// Перевод строки интерфейса: tr('English', 'Русский').
/// Обе версии лежат рядом в коде — удобно править и работает с интерполяцией ($login и т.п.).
String tr(String en, String ru) => UserPrefs.instance.isRu ? ru : en;

/// Локальные настройки по пользователям: игнор и переименования.
/// Хранятся в Hive-боксах 'IgnoredUsers' (login -> true) и 'UserAliases' (login -> имя).
/// Это ChangeNotifier: чат подписан на него и перерисовывается при изменениях.
class UserPrefs extends ChangeNotifier {
  UserPrefs._();
  static final UserPrefs instance = UserPrefs._();

  Box? _ignored;
  Box? _aliases;
  Box? _mod;
  Box? _colors;

  /// id сообщений игнорируемых юзеров, которые пользователь раскрыл тапом.
  final Set<String> revealed = {};

  Future<void> init() async {
    _ignored = await Hive.openBox('IgnoredUsers');
    _aliases = await Hive.openBox('UserAliases');
    _mod = await Hive.openBox('ModSettings');
    _colors = await Hive.openBox('UserColors');
  }

  // ---------- вид чата ----------

  /// Значки у ника: 0 — все, 1 — только роли (стример/мод/VIP/саб), 2 — скрыть все.
  int get badgeMode => _g<int>('badgeMode', 0);
  Future<void> setBadgeMode(int v) async {
    await _mod?.put('badgeMode', v);
    notifyListeners();
  }

  /// Стиль @упоминаний в тексте: 0 обычный, 1 акцент, 2 плашка, 3 рамка, 4 цвет ника.
  int get mentionStyle => _g<int>('mentionStyle', 1);
  Future<void> setMentionStyle(int v) async {
    await _mod?.put('mentionStyle', v);
    notifyListeners();
  }

  /// Размер шрифта чата (ник + текст), px. Применяется и к списку зрителей.
  static const double minFont = 10, maxFont = 28;
  double get chatFontSize {
    final v = _g<num>('chatFontSize', 14);
    return v.toDouble().clamp(minFont, maxFont);
  }

  Future<void> setChatFontSize(double v) async {
    await _mod?.put('chatFontSize', v.clamp(minFont, maxFont));
    notifyListeners();
  }

  /// Рамка 2px цвета акцента у кнопок и окон.
  bool get accentBorders => _g<bool>('accentBorders', false);
  Future<void> setAccentBorders(bool v) async {
    await _mod?.put('accentBorders', v);
    appearance.value++;
    notifyListeners();
  }

  /// Полупрозрачные панели (шторка, нижние карточки). По умолчанию выключено — сплошной фон.
  bool get translucent => _g<bool>('translucent', false);
  Future<void> setTranslucent(bool v) async {
    await _mod?.put('translucent', v);
    appearance.value++;
    notifyListeners();
  }

  /// Своя альфа для панели: сплошная, если полупрозрачность выключена.
  int panelAlpha(int translucentAlpha) => translucent ? translucentAlpha : 255;

  /// Локальный цвет ника для юзера (выбран в карточке), или null.
  Color? userColor(String? login) {
    if (login == null) return null;
    final raw = _colors?.get(login.toLowerCase());
    final v = raw is int ? raw : null;
    return v == null ? null : Color(v);
  }

  Future<void> setUserColor(String login, Color? c) async {
    if (c == null) {
      await _colors?.delete(login.toLowerCase());
    } else {
      await _colors?.put(login.toLowerCase(), c.toARGB32());
    }
    notifyListeners();
  }

  // ---------- производительность ----------

  /// Максимум сообщений на канал: столько рисуется И хранится. Лишние (самые старые)
  /// удаляются автоматически — это и есть автоочистка.
  int get renderLimit => _g<int>('renderLimit', 300);
  Future<void> setRenderLimit(int v) async {
    final n = v.clamp(20, 1000);
    await _mod?.put('renderLimit', n);
    twitch.ircMaxMessages = n;
    notifyListeners();
  }

  /// Размытие (BackdropFilter) под панелями. По умолчанию выключено — главный источник фризов.
  bool get blur => _g<bool>('blur', false);
  Future<void> setBlur(bool v) async {
    await _mod?.put('blur', v);
    notifyListeners();
  }

  /// Принудительная перерисовка чата (после очистки сообщений).
  void bump() => notifyListeners();

  // ---------- язык и оформление ----------

  /// Отдельный сигнал для MaterialApp: меняется только при смене языка/фона,
  /// чтобы тап по «игнору» не пересобирал тему всего приложения.
  final ValueNotifier<int> appearance = ValueNotifier(0);

  /// 'ru' или 'en'. По умолчанию — язык системы.
  String get lang {
    final v = _g<String?>('lang', null);
    if (v != null) return v;
    return PlatformDispatcher.instance.locale.languageCode == 'ru' ? 'ru' : 'en';
  }

  bool get isRu => lang == 'ru';

  Future<void> setLang(String v) async {
    await _mod?.put('lang', v);
    appearance.value++;
    notifyListeners();
  }

  /// Последний выбранный хостинг для загрузки файлов.
  String get uploadHost => _g<String>('uploadHost', 'kappa');
  Future<void> setUploadHost(String v) async => _mod?.put('uploadHost', v);

  /// Автосохранение настроек в файл (Загрузки/ChatsenMod). По умолчанию включено.
  bool get autoBackup => _g<bool>('autoBackup', true);
  Future<void> setAutoBackup(bool v) async {
    await _mod?.put('autoBackup', v);
    notifyListeners();
  }

  /// Путь и время последнего автосохранения — показываем в настройках.
  String? get lastBackupPath => _g<String?>('lastBackupPath', null);
  DateTime? get lastBackupTime {
    final v = _g<int?>('lastBackupTime', null);
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  Future<void> markBackup(String path) async {
    await _mod?.put('lastBackupPath', path);
    await _mod?.put('lastBackupTime', DateTime.now().millisecondsSinceEpoch);
  }

  /// Первый запуск после установки: предложить восстановление один раз.
  bool get restoreOffered => _g<bool>('restoreOffered', false);
  Future<void> setRestoreOffered() async => _mod?.put('restoreOffered', true);

  /// Всё, что хранит мод (для экспорта/импорта).
  Map<String, dynamic> exportMod() => {
        'mod': {for (final k in _mod?.keys ?? const []) '$k': _mod!.get(k)}..removeWhere((k, _) => k.startsWith('lastBackup') || k == 'restoreOffered'),
        'ignored': [for (final k in _ignored?.keys ?? const []) '$k'],
        'aliases': {for (final k in _aliases?.keys ?? const []) '$k': _aliases!.get(k)},
        'userColors': {for (final k in _colors?.keys ?? const []) '$k': _colors!.get(k)},
      };

  Future<void> importMod(Map data) async {
    final mod = data['mod'];
    if (mod is Map) {
      for (final e in mod.entries) {
        await _mod?.put(e.key, e.value);
      }
    }
    final ignored = data['ignored'];
    if (ignored is List) {
      await _ignored?.clear();
      for (final l in ignored) {
        await _ignored?.put('$l'.toLowerCase(), true);
      }
    }
    final aliases = data['aliases'];
    if (aliases is Map) {
      await _aliases?.clear();
      for (final e in aliases.entries) {
        await _aliases?.put('${e.key}'.toLowerCase(), '${e.value}');
      }
    }
    final colors = data['userColors'];
    if (colors is Map) {
      await _colors?.clear();
      for (final e in colors.entries) {
        if (e.value is int) await _colors?.put('${e.key}'.toLowerCase(), e.value);
      }
    }
    appearance.value++;
    notifyListeners();
  }

  /// Свёрнутые группы в окне эмоутов (ключи вида «tab:группа»).
  Set<String> get pickerCollapsed {
    final v = _mod?.get('pickerCollapsed');
    return v is List ? v.map((e) => '$e').toSet() : <String>{};
  }

  Future<void> togglePickerGroup(String key) async {
    final set = pickerCollapsed;
    if (!set.remove(key)) set.add(key);
    await _mod?.put('pickerCollapsed', set.toList());
  }

  /// Свой цвет акцента (из палитры) или null — используется шаблон из темы.
  Color? get accent {
    final v = _g<int?>('accentColor', null);
    return v == null ? null : Color(v);
  }

  Future<void> setAccent(Color? c) async {
    if (c == null) {
      await _mod?.delete('accentColor');
    } else {
      await _mod?.put('accentColor', c.toARGB32());
    }
    appearance.value++;
    notifyListeners();
  }

  /// Цвет фона (ARGB) или null — стандартная тема.
  Color? get background {
    final v = _g<int?>('bgColor', null);
    return v == null ? null : Color(v);
  }

  Future<void> setBackground(Color? c) async {
    if (c == null) {
      await _mod?.delete('bgColor');
    } else {
      await _mod?.put('bgColor', c.toARGB32());
    }
    appearance.value++;
    notifyListeners();
  }

  /// Пересобрать вообще все виджеты приложения, включая страницы под текущей
  /// (после смены языка: строки читаются через tr() во время build).
  static void rebuildAll([BuildContext? _]) {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
  }

  /// Безопасное чтение настройки: значение не того типа (например, из чужого файла) → дефолт.
  T _g<T>(String key, T fallback) {
    final v = _mod?.get(key);
    return v is T ? v : fallback;
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

  String? aliasOf(String? login) {
    final v = login == null ? null : _aliases?.get(_k(login));
    return v is String ? v : null;
  }

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
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(ctx).bottom + MediaQuery.viewInsetsOf(ctx).bottom),
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
