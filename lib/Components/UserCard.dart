import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '/BlockedUsers/BlockedUsersCubit.dart';
import '/Pages/Search.dart';
import 'ChatInputBox.dart';
import 'EmotePopup.dart' show ChatsenActionButton;
import 'UI/NetworkImageWrapper.dart';
import 'UserPrefs.dart';
import 'AppearanceSettings.dart' show ColorPickerDialog;

/// Карточка профиля пользователя (bottom sheet).
/// Открывается тапом по нику в чате, тапом по @упоминанию и из списка юзеров.
class UserCard extends StatefulWidget {
  final String login;
  final twitch.Channel? channel;

  const UserCard({Key? key, required this.login, this.channel}) : super(key: key);

  static Future<void> show(BuildContext context, {required String login, twitch.Channel? channel}) async {
    final clean = login.replaceAll(RegExp(r'^@+|[,.:!?]+$'), '');
    if (clean.isEmpty) return;
    await showChatsenSheet(context, (_) => UserCard(login: clean, channel: channel));
  }

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserInfo {
  final String login;
  final String displayName;
  final String? avatar;
  final String? description;
  final DateTime? createdAt;
  final String? broadcasterType;
  final String? id;

  _UserInfo({required this.login, required this.displayName, this.avatar, this.description, this.createdAt, this.broadcasterType, this.id});
}

class _UserCardState extends State<UserCard> {
  // Кэш, чтобы не дёргать Helix на каждый тап по одному и тому же нику.
  static final Map<String, _UserInfo> _cache = {};

  _UserInfo? info;
  String? error;
  bool loading = true;

  twitch.Credentials? get _credentials {
    final c = widget.channel?.transmitter?.credentials ?? widget.channel?.client?.credentials;
    if (c?.token == null || c?.clientId == null) return null;
    return c;
  }

  @override
  void initState() {
    super.initState();
    UserPrefs.instance.addListener(_onPrefs);
    _load();
  }

  @override
  void dispose() {
    UserPrefs.instance.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final key = widget.login.toLowerCase();
    if (_cache.containsKey(key)) {
      setState(() {
        info = _cache[key];
        loading = false;
      });
      return;
    }
    final creds = _credentials;
    if (creds == null) {
      setState(() {
        loading = false;
        error = tr('Log in to see the avatar and account age', 'Войдите в аккаунт, чтобы видеть аватар и дату регистрации');
      });
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('https://api.twitch.tv/helix/users?login=${Uri.encodeQueryComponent(key)}'),
        headers: {'Client-ID': creds.clientId!, 'Authorization': 'Bearer ${creds.token}'},
      );
      final data = (jsonDecode(res.body)['data'] as List?) ?? [];
      if (data.isEmpty) {
        if (!mounted) return;
        setState(() {
          loading = false;
          error = res.statusCode == 200 ? tr('User not found (banned or deleted)', 'Пользователь не найден (забанен или удалён)') : 'Helix: HTTP ${res.statusCode}';
        });
        return;
      }
      final u = data.first;
      final parsed = _UserInfo(
        login: u['login'],
        displayName: u['display_name'] ?? u['login'],
        avatar: u['profile_image_url'],
        description: (u['description'] as String?)?.trim(),
        createdAt: DateTime.tryParse(u['created_at'] ?? ''),
        broadcasterType: u['broadcaster_type'],
        id: u['id'],
      );
      _cache[key] = parsed;
      if (!mounted) return;
      setState(() {
        info = parsed;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = tr('Network error: $e', 'Ошибка сети: $e');
      });
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
  }

  String _age(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days < 31) return tr('${days}d', '$days дн.');
    if (days < 365) return tr('${(days / 30.4).floor()}mo', '${(days / 30.4).floor()} мес.');
    final y = days ~/ 365;
    final m = ((days % 365) / 30.4).floor();
    return m > 0 ? tr('${y}y ${m}mo', '$y г. $m мес.') : tr('${y}y', '$y г.');
  }

  Future<void> _rename(String login, String display) async {
    final ctrl = TextEditingController(text: UserPrefs.instance.aliasOf(login) ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Name for $display', 'Имя для $display')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 32,
          decoration: InputDecoration(hintText: tr('Local name (only you see it)', 'Локальное имя (видно только вам)')),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(''), child: Text(tr('Reset', 'Сбросить'))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Cancel', 'Отмена'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return; // отмена
    await UserPrefs.instance.setAlias(login, result);
    _snack(result.trim().isEmpty ? tr('Name reset', 'Имя сброшено') : tr('$login is now \'${result.trim()}\'', '$login теперь «${result.trim()}»'));
  }

  @override
  Widget build(BuildContext context) {
    final prefs = UserPrefs.instance;
    final login = info?.login ?? widget.login;
    final display = info?.displayName ?? widget.login;
    final alias = prefs.aliasOf(login);
    final ignored = prefs.isIgnored(login);
    final blocked = context.watch<BlockedUsersCubit>().state.map((e) => e.toLowerCase()).contains(login.toLowerCase());
    final input = widget.channel != null ? ChatInputBoxState.of(widget.channel!) : null;
    final msgCount = widget.channel?.messages.where((m) => m.user?.login?.toLowerCase() == login.toLowerCase()).length ?? 0;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: info?.avatar != null
                        ? NetworkImageW(info!.avatar!, fit: BoxFit.cover)
                        : Container(color: theme.dividerColor, child: loading ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.person, size: 32)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(alias ?? display, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      if (alias != null || display.toLowerCase() != login.toLowerCase())
                        SelectableText(alias != null ? '$display · $login' : login, style: theme.textTheme.bodyMedium),
                      if (info?.createdAt != null)
                        Text(
                          tr('Account: ', 'Аккаунт: ') + '${info!.createdAt!.day.toString().padLeft(2, '0')}.${info!.createdAt!.month.toString().padLeft(2, '0')}.${info!.createdAt!.year} (${_age(info!.createdAt!)})',
                          style: theme.textTheme.bodySmall,
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (widget.channel != null) Text(tr('Messages: $msgCount', 'Сообщений: $msgCount'), style: theme.textTheme.bodySmall),
                          if (info?.broadcasterType != null && info!.broadcasterType!.isNotEmpty) Text(info!.broadcasterType!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                          if (ignored) Text(tr('ignored', 'в игноре'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
                          if (blocked) Text(tr('blocked', 'заблокирован'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (info?.description != null && info!.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(info!.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          ],
          const SizedBox(height: 12),
          // Ряд 1 — частые действия
          Row(
            children: [
              if (input != null)
                Expanded(
                  child: ChatsenActionButton(
                    icon: Icons.alternate_email,
                    label: tr('Mention', 'Упомянуть'),
                    onTap: () {
                      input.insertMention(login);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              Expanded(
                child: ChatsenActionButton(
                  icon: Icons.copy,
                  label: tr('Name', 'Ник'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: login));
                    _snack(tr('Username \'$login\' copied', 'Ник «$login» скопирован'));
                  },
                ),
              ),
              if (widget.channel != null)
                Expanded(
                  child: ChatsenActionButton(
                    icon: Icons.history,
                    label: tr('Messages', 'Сообщения'),
                    onTap: () {
                      final msg = widget.channel!.messages.lastWhereOrNull((m) => m.user?.login?.toLowerCase() == login.toLowerCase());
                      final nav = Navigator.of(context);
                      nav.pop();
                      if (msg?.user == null) {
                        _snack(tr('No messages from $login in this chat', 'Нет сообщений от $login в этом чате'));
                        return;
                      }
                      nav.push(MaterialPageRoute(builder: (_) => SearchPage(channel: widget.channel, user: msg!.user)));
                    },
                  ),
                ),
              Expanded(
                child: ChatsenActionButton(
                  icon: Icons.open_in_new,
                  label: 'twitch.tv',
                  onTap: () => launchUrl(Uri.parse('https://www.twitch.tv/$login'), mode: LaunchMode.externalApplication),
                ),
              ),
            ],
          ),
          // Ряд 2 — управление
          Row(
            children: [
              Expanded(
                child: ChatsenActionButton(
                  icon: Icons.palette_outlined,
                  label: tr('Color', 'Цвет'),
                  // кнопка окрашена в текущий свой цвет ника
                  color: prefs.userColor(login),
                  onTap: () async {
                    final picked = await ColorPickerDialog.show(
                      context,
                      initial: prefs.userColor(login) ?? theme.colorScheme.primary,
                      title: tr('Nickname color', 'Цвет ника'),
                      sample: alias ?? display,
                      allowReset: prefs.userColor(login) != null,
                    );
                    if (picked == null) return;
                    await prefs.setUserColor(login, picked == ColorPickerDialog.reset ? null : picked);
                  },
                ),
              ),
              Expanded(
                child: ChatsenActionButton(
                  icon: Icons.drive_file_rename_outline,
                  label: alias != null ? tr('Name ✓', 'Имя ✓') : tr('Rename', 'Имя'),
                  active: alias != null,
                  onTap: () => _rename(login, display),
                ),
              ),
              Expanded(
                child: ChatsenActionButton(
                  icon: ignored ? Icons.visibility : Icons.visibility_off,
                  label: ignored ? tr('Unignore', 'Не игнор') : tr('Ignore', 'Игнор'),
                  active: ignored,
                  onTap: () async {
                    await prefs.setIgnored(login, !ignored);
                    _snack(ignored ? tr('Messages from $login are visible again', 'Сообщения $login снова видны') : tr('Messages from $login are collapsed (tap to show)', 'Сообщения $login свёрнуты (тап — показать)'));
                  },
                ),
              ),
              Expanded(
                child: ChatsenActionButton(
                  icon: blocked ? Icons.lock_open : Icons.block,
                  label: blocked ? tr('Unblock', 'Разблок.') : tr('Block', 'Блок'),
                  color: blocked ? null : theme.colorScheme.error,
                  active: blocked,
                  onTap: () async {
                    final cubit = context.read<BlockedUsersCubit>();
                    if (blocked) {
                      final existing = cubit.state.firstWhere((e) => e.toLowerCase() == login.toLowerCase());
                      await cubit.remove(existing);
                      _snack(tr('$login unblocked', '$login разблокирован'));
                    } else {
                      await cubit.add(login.toLowerCase());
                      _snack(tr('$login is fully hidden from chat', '$login полностью скрыт из чата'));
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
