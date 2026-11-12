import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '/Accounts/AccountModel.dart';
import '/Commands/Command.dart';
import '/DataExport.dart';
import '/Mentions/CustomMention.dart';
import 'UserPrefs.dart';

/// DearKing mod: резервная копия всех настроек.
///
/// * Экспорт/импорт файлом или через буфер обмена.
/// * Автосохранение в «Загрузки/ChatsenMod/chatsen-backup.json» при сворачивании приложения
///   (без токенов входа — файл лежит в общей папке).
/// * После переустановки при первом запуске предлагается восстановить настройки из файла.
class Backup {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static const _dir = '/storage/emulated/0/Download/ChatsenMod';

  static Future<Box> _box(String name) async => Hive.isBoxOpen(name) ? Hive.box(name) : Hive.openBox(name);

  /// Собрать всё в одну карту. [withAccounts] — включать ли токены входа.
  static Future<Map<String, dynamic>> build({bool withAccounts = false}) async {
    final data = buildExportData(
      settingsBox: await _box('Settings'),
      themeBox: await _box('Theme'),
      accountsBox: await _box('Accounts'),
      commandsBox: await _box('Commands'),
      customMentionsBox: await _box('CustomMentions'),
      blockedUsersBox: await _box('BlockedUsers'),
    );
    if (!withAccounts) data.remove('accounts');
    final channels = await _box('Channels');
    return {
      'format': 'chatsen-mod-backup',
      'version': 1,
      'created': DateTime.now().toIso8601String(),
      ...data,
      'channels': List<String>.from(channels.values.map((e) => '$e')),
      ...UserPrefs.instance.exportMod(),
    };
  }

  static Future<String> buildJson({bool withAccounts = false}) async => const JsonEncoder.withIndent('  ').convert(await build(withAccounts: withAccounts));

  /// Записать данные из копии в хранилище. Блоки (настройки, тема) перечитываются при перезапуске.
  static Future<void> restore(Map data) async {
    final settings = data['settings'];
    if (settings is Map) {
      final box = await _box('Settings');
      for (final e in settings.entries) {
        await box.put(e.key, e.value);
      }
    }
    final theme = data['theme'];
    if (theme is Map) {
      final box = await _box('Theme');
      if (theme['mode'] != null) await box.put('themeMode', theme['mode']);
      if (theme['colorScheme'] != null) await box.put('themeColorScheme', theme['colorScheme']);
      await box.put('themeHighContrast', theme['highContrast'] ?? false);
    }
    final accounts = data['accounts'];
    if (accounts is List && accounts.isNotEmpty) {
      final box = await _box('Accounts');
      final existing = box.values.map((a) => (a as AccountModel).login).toSet();
      for (final a in accounts) {
        if (a is! Map || existing.contains(a['login'])) continue;
        await box.add(AccountModel(login: a['login'], token: a['token'], id: a['id'], clientId: a['clientId'], isActive: a['isActive'] ?? false));
      }
    }
    final commands = data['commands'];
    if (commands is List) {
      final box = await _box('Commands');
      await box.clear();
      for (final c in commands) {
        if (c is Map) await box.add(Command(trigger: '${c['trigger']}', command: '${c['command']}'));
      }
    }
    final mentions = data['customMentions'];
    if (mentions is List) {
      final box = await _box('CustomMentions');
      await box.clear();
      for (final m in mentions) {
        if (m is! Map) continue;
        await box.add(CustomMention(
          pattern: '${m['pattern']}',
          showInMentions: m['showInMentions'] ?? true,
          sendNotification: m['sendNotification'] ?? true,
          playSound: m['playSound'] ?? true,
          enableRegex: m['enableRegex'] ?? false,
          caseSensitive: m['caseSensitive'] ?? false,
        ));
      }
    }
    final blocked = data['blockedUsers'];
    if (blocked is List) {
      final box = await _box('BlockedUsers');
      await box.clear();
      await box.addAll(blocked.map((e) => '$e'));
    }
    final channels = data['channels'];
    if (channels is List && channels.isNotEmpty) {
      final box = await _box('Channels');
      await box.clear();
      await box.addAll(channels.map((e) => '$e'));
    }
    await UserPrefs.instance.importMod(data);
  }

  static Map _parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map || (j['settings'] == null && j['mod'] == null)) {
      throw tr('This is not a Chatsen backup', 'Это не резервная копия Chatsen');
    }
    return j;
  }

  // ---------- автосохранение ----------

  static bool _saving = false;

  /// Тихо сохранить копию (без токенов). Возвращает путь или null.
  static Future<String?> autoSave() async {
    if (!UserPrefs.instance.autoBackup || _saving || !Platform.isAndroid) return null;
    _saving = true;
    try {
      final json = await buildJson();
      // 1) общая папка «Загрузки» — переживает удаление приложения
      for (final name in ['chatsen-backup.json', 'chatsen-backup-${_installTag()}.json']) {
        try {
          final f = File('$_dir/$name');
          await f.parent.create(recursive: true);
          await f.writeAsString(json, flush: true);
          await UserPrefs.instance.markBackup(f.path);
          return f.path;
        } catch (_) {
          // файл от прошлой установки нельзя перезаписать (Android считает его чужим) — пробуем другое имя
        }
      }
      // 2) запасной вариант — папка приложения (удалится вместе с ним)
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/chatsen-backup.json');
      await f.writeAsString(json, flush: true);
      await UserPrefs.instance.markBackup(f.path);
      return f.path;
    } catch (_) {
      return null;
    } finally {
      _saving = false;
    }
  }

  static String _installTag() {
    // метка установки = время первого автосохранения в этой установке
    final t = UserPrefs.instance.lastBackupTime ?? DateTime.now();
    return '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
  }

  // ---------- действия из настроек ----------

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));

  static Future<bool?> _askAccounts(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Include login?', 'Включить вход в аккаунт?')),
          content: Text(tr(
            'The file will contain your Twitch login token. Anyone with the file can use your account in chat — do not share it.',
            'В файл попадёт токен входа Twitch. С этим файлом можно писать в чат от вашего имени — никому его не передавайте.',
          )),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Settings only', 'Только настройки'))),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Include login', 'С входом'))),
          ],
        ),
      );

  static Future<void> exportToFile(BuildContext context) async {
    final withAccounts = await _askAccounts(context);
    if (withAccounts == null) return;
    final json = await buildJson(withAccounts: withAccounts);
    final now = DateTime.now();
    final name = 'chatsen-mod-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: tr('Save backup', 'Сохранить копию'),
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (path != null && context.mounted) _snack(context, tr('Saved', 'Сохранено'));
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  static Future<void> exportToClipboard(BuildContext context) async {
    final withAccounts = await _askAccounts(context);
    if (withAccounts == null) return;
    await Clipboard.setData(ClipboardData(text: await buildJson(withAccounts: withAccounts)));
    if (context.mounted) _snack(context, tr('Copied to clipboard', 'Скопировано в буфер обмена'));
  }

  static Future<void> importFromFile(BuildContext context) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      final bytes = r?.files.first.bytes;
      if (bytes == null) return;
      await _apply(context, utf8.decode(bytes));
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  static Future<void> importFromClipboard(BuildContext context) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.trim().isEmpty) {
      if (context.mounted) _snack(context, tr('Clipboard is empty', 'Буфер обмена пуст'));
      return;
    }
    if (context.mounted) await _apply(context, text);
  }

  static Future<void> _apply(BuildContext context, String text) async {
    try {
      final data = _parse(text);
      await restore(data);
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Settings restored', 'Настройки восстановлены')),
          content: Text(tr('Restart the app to apply everything.', 'Перезапустите приложение, чтобы всё применилось.')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Later', 'Позже'))),
            FilledButton(onPressed: () => SystemNavigator.pop(), child: Text(tr('Close app', 'Закрыть приложение'))),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) _snack(context, '$e');
    }
  }

  /// Первый запуск после установки: если аккаунтов и каналов нет — предложить восстановление.
  static Future<void> maybeOfferRestore() async {
    if (UserPrefs.instance.restoreOffered) return;
    await UserPrefs.instance.setRestoreOffered();
    final accounts = await _box('Accounts');
    final channels = await _box('Channels');
    if (accounts.isNotEmpty || channels.isNotEmpty) return; // это обновление, а не новая установка
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Restore settings?', 'Восстановить настройки?')),
        content: Text(tr(
          'If you used Chatsen Mod before, pick the backup file: Downloads → ChatsenMod → chatsen-backup.json',
          'Если вы уже пользовались Chatsen Mod — выберите файл копии: Загрузки → ChatsenMod → chatsen-backup.json',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('No', 'Нет'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Pick file', 'Выбрать файл'))),
        ],
      ),
    );
    if (yes == true && context.mounted) await importFromFile(context);
  }
}
