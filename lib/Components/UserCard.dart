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
import 'UI/NetworkImageWrapper.dart';

/// Карточка профиля пользователя (bottom sheet).
/// Открывается тапом по нику в чате, тапом по @упоминанию и из списка юзеров.
class UserCard extends StatefulWidget {
  final String login;
  final twitch.Channel? channel;

  const UserCard({Key? key, required this.login, this.channel}) : super(key: key);

  static Future<void> show(BuildContext context, {required String login, twitch.Channel? channel}) async {
    final clean = login.replaceAll(RegExp(r'^@+|[,.:!?]+$'), '');
    if (clean.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => UserCard(login: clean, channel: channel),
    );
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
    _load();
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
        error = 'Войдите в аккаунт, чтобы видеть аватар и дату регистрации';
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
        setState(() {
          loading = false;
          error = res.statusCode == 200 ? 'Пользователь не найден (забанен или удалён)' : 'Helix: HTTP ${res.statusCode}';
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
        error = 'Ошибка сети: $e';
      });
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
  }

  String _age(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days < 31) return '$days дн.';
    if (days < 365) return '${(days / 30.4).floor()} мес.';
    final y = days ~/ 365;
    final m = ((days % 365) / 30.4).floor();
    return m > 0 ? '$y г. $m мес.' : '$y г.';
  }

  @override
  Widget build(BuildContext context) {
    final login = info?.login ?? widget.login;
    final display = info?.displayName ?? widget.login;
    final blocked = context.watch<BlockedUsersCubit>().state.map((e) => e.toLowerCase()).contains(login.toLowerCase());
    final input = widget.channel != null ? ChatInputBoxState.of(widget.channel!) : null;
    final msgCount = widget.channel?.messages.where((m) => m.user?.login?.toLowerCase() == login.toLowerCase()).length ?? 0;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                    // Ник выделяемый — можно скопировать кусок вручную.
                    SelectableText(display, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    if (display.toLowerCase() != login.toLowerCase()) SelectableText(login, style: theme.textTheme.bodyMedium),
                    if (info?.createdAt != null)
                      Text(
                        'Аккаунт: ${info!.createdAt!.day.toString().padLeft(2, '0')}.${info!.createdAt!.month.toString().padLeft(2, '0')}.${info!.createdAt!.year} (${_age(info!.createdAt!)})',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (info?.broadcasterType != null && info!.broadcasterType!.isNotEmpty) Text(info!.broadcasterType!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                    if (widget.channel != null) Text('Сообщений в этом чате: $msgCount', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (info?.description != null && info!.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(info!.description!, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (input != null)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.alternate_email),
                  label: const Text('Упомянуть'),
                  onPressed: () {
                    input.insertMention(login);
                    Navigator.of(context).pop();
                  },
                ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.copy),
                label: const Text('Копировать ник'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: login));
                  _snack('Ник «$login» скопирован');
                },
              ),
              if (widget.channel != null)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.history),
                  label: const Text('Сообщения'),
                  onPressed: () {
                    final msg = widget.channel!.messages.lastWhereOrNull(
                      (m) => m.user?.login?.toLowerCase() == login.toLowerCase(),
                    );
                    final nav = Navigator.of(context);
                    nav.pop();
                    if (msg?.user == null) {
                      _snack('Нет сообщений от $login в этом чате');
                      return;
                    }
                    nav.push(MaterialPageRoute(builder: (_) => SearchPage(channel: widget.channel, user: msg!.user)));
                  },
                ),
              FilledButton.tonalIcon(
                icon: Icon(blocked ? Icons.lock_open : Icons.block),
                label: Text(blocked ? 'Разблокировать' : 'Заблокировать'),
                style: blocked ? null : FilledButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () async {
                  final cubit = context.read<BlockedUsersCubit>();
                  if (blocked) {
                    final existing = cubit.state.firstWhere((e) => e.toLowerCase() == login.toLowerCase());
                    await cubit.remove(existing);
                    _snack('$login разблокирован');
                  } else {
                    await cubit.add(login.toLowerCase());
                    _snack('$login скрыт из чата');
                  }
                },
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('twitch.tv'),
                onPressed: () => launchUrl(Uri.parse('https://www.twitch.tv/$login'), mode: LaunchMode.externalApplication),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
