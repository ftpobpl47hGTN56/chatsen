import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'UI/NetworkImageWrapper.dart';
import '/Components/UserPrefs.dart';

/// Окно добавления чатов (DearKing mod).
///  * пустое поле — список каналов, на которые вы зафоловлены (LIVE сверху, с онлайном и игрой);
///  * ввод текста — фильтр по фолловам + поиск по всему Twitch (Helix search/channels);
///  * тап по строке отмечает канал, кнопка «Добавить (N)» подключает все отмеченные;
///  * по-старому можно ввести ники через запятую/пробел и нажать Enter.
class ChannelJoinModal extends StatefulWidget {
  final twitch.Client? client;
  final Function refresh;

  const ChannelJoinModal({
    Key? key,
    required this.client,
    required this.refresh,
  }) : super(key: key);

  @override
  _ChannelJoinModalState createState() => _ChannelJoinModalState();
}

class _Ch {
  final String login;
  final String name;
  String? avatar;
  bool live;
  int? viewers;
  String? game;
  String? title;
  bool followed;

  _Ch({required this.login, required this.name, this.avatar, this.live = false, this.viewers, this.game, this.title, this.followed = false});
}

class _ChannelJoinModalState extends State<ChannelJoinModal> {
  final textEditingController = TextEditingController();
  final Set<String> selected = {};

  // Фолловы кэшируем на время жизни приложения — список меняется редко.
  static List<_Ch>? _followsCache;
  static DateTime? _followsTime;

  List<_Ch> follows = [];
  List<_Ch> searchResults = [];
  bool loadingFollows = true;
  bool searching = false;
  String? followsError;
  Timer? _debounce;

  twitch.Credentials? get _creds {
    final c = widget.client?.credentials;
    if (c != null && c.token != null && c.clientId != null && c.id != null) return c;
    final t = widget.client?.transmitters[null]?.credentials;
    if (t != null && t.token != null && t.clientId != null && t.id != null) return t;
    return null;
  }

  Map<String, String> get _headers => {'Client-ID': _creds!.clientId!, 'Authorization': 'Bearer ${_creds!.token}'};

  bool _joined(String login) => widget.client?.channels.any((c) => c.name?.toLowerCase() == '#${login.toLowerCase()}') ?? false;

  @override
  void initState() {
    super.initState();
    _loadFollows();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    textEditingController.dispose();
    super.dispose();
  }

  Future<dynamic> _get(String url) async {
    final res = await http.get(Uri.parse(url), headers: _headers);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw _ScopeError('${body['message'] ?? res.statusCode}');
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}: ${body['message'] ?? ''}');
    return body;
  }

  Future<void> _loadFollows({bool force = false}) async {
    if (_creds == null) {
      setState(() {
        loadingFollows = false;
        followsError = tr('Log in to see the channels you follow', 'Войдите в аккаунт, чтобы видеть свои подписки');
      });
      return;
    }
    if (!force && _followsCache != null && _followsTime != null && DateTime.now().difference(_followsTime!).inMinutes < 10) {
      setState(() {
        follows = _followsCache!;
        loadingFollows = false;
      });
      _refreshLive(); // онлайн обновляем всегда
      return;
    }
    setState(() {
      loadingFollows = true;
      followsError = null;
    });
    try {
      final uid = _creds!.id;
      final list = <_Ch>[];
      String? cursor;
      // Helix отдаёт максимум 100 за раз — листаем курсором (лимит 10 страниц = 1000 каналов)
      for (var page = 0; page < 10; page++) {
        final j = await _get('https://api.twitch.tv/helix/channels/followed?user_id=$uid&first=100${cursor != null ? '&after=$cursor' : ''}');
        for (final f in (j['data'] as List)) {
          list.add(_Ch(login: f['broadcaster_login'], name: f['broadcaster_name'] ?? f['broadcaster_login'], followed: true));
        }
        cursor = j['pagination']?['cursor'];
        if (cursor == null || cursor.isEmpty) break;
      }
      // аватарки пачками по 100
      for (var i = 0; i < list.length; i += 100) {
        final chunk = list.sublist(i, i + 100 > list.length ? list.length : i + 100);
        final j = await _get('https://api.twitch.tv/helix/users?${chunk.map((c) => 'login=${c.login}').join('&')}');
        final byLogin = {for (final u in (j['data'] as List)) (u['login'] as String): u['profile_image_url'] as String?};
        for (final c in chunk) {
          c.avatar = byLogin[c.login];
        }
      }
      follows = list;
      _followsCache = list;
      _followsTime = DateTime.now();
      if (!mounted) return;
      setState(() => loadingFollows = false);
      await _refreshLive();
    } on _ScopeError {
      if (!mounted) return;
      setState(() {
        loadingFollows = false;
        followsError = tr('No access to your follows. Log in again (Settings → Accounts → re-login) to grant the user:read:follows permission.', 'Нет доступа к подпискам. Перелогиньтесь в аккаунт (Настройки → Аккаунты → войти заново), чтобы выдать разрешение user:read:follows.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingFollows = false;
        followsError = tr('Could not load follows: $e', 'Не удалось загрузить подписки: $e');
      });
    }
  }

  /// Кто из фолловов сейчас в эфире (streams/followed), сортировка LIVE → по онлайну.
  Future<void> _refreshLive() async {
    try {
      final j = await _get('https://api.twitch.tv/helix/streams/followed?user_id=${_creds!.id}&first=100');
      final live = {for (final s in (j['data'] as List)) (s['user_login'] as String): s};
      for (final c in follows) {
        final s = live[c.login];
        c.live = s != null;
        c.viewers = s?['viewer_count'];
        c.game = s?['game_name'];
        c.title = s?['title'];
      }
      follows.sort((a, b) {
        if (a.live != b.live) return a.live ? -1 : 1;
        if (a.live) return (b.viewers ?? 0).compareTo(a.viewers ?? 0);
        return a.login.compareTo(b.login);
      });
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _onQuery(String q) {
    setState(() {});
    _debounce?.cancel();
    final query = q.trim().replaceAll('#', '');
    // ввод через запятую/пробел — это старый режим «несколько ников», поиск не нужен
    if (query.length < 2 || query.contains(',') || query.contains(' ') || _creds == null) {
      setState(() {
        searchResults = [];
        searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => searching = true);
    try {
      final j = await _get('https://api.twitch.tv/helix/search/channels?query=${Uri.encodeQueryComponent(query)}&first=20');
      if (textEditingController.text.trim().replaceAll('#', '') != query) return; // устарело
      final followed = {for (final f in follows) f.login};
      searchResults = [
        for (final c in (j['data'] as List))
          _Ch(
            login: c['broadcaster_login'],
            name: c['display_name'] ?? c['broadcaster_login'],
            avatar: c['thumbnail_url'],
            live: c['is_live'] == true,
            game: c['game_name'],
            title: c['title'],
            followed: followed.contains(c['broadcaster_login']),
          ),
      ];
    } catch (_) {
      searchResults = [];
    }
    if (mounted) setState(() => searching = false);
  }

  Future<void> _join(Iterable<String> logins) async {
    final names = logins.map((v) => '#${v.replaceAll('#', '').trim().toLowerCase()}').where((n) => n.length > 1).toSet().toList();
    names.removeWhere((n) => widget.client!.channels.any((channel) => channel.name == n));
    if (names.isNotEmpty) {
      await widget.client!.joinChannels(names);
      var channelsBox = await Hive.openBox('Channels');
      await channelsBox.clear();
      await channelsBox.addAll(widget.client!.channels.map((channel) => channel.name));
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.refresh();
  }

  void _submitText() {
    final typed = textEditingController.text.replaceAll(' ', ',').split(',').where((v) => v.trim().isNotEmpty);
    _join([...selected, ...typed]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = textEditingController.text.trim().replaceAll('#', '').toLowerCase();
    final filteredFollows = query.isEmpty ? follows : follows.where((c) => c.login.contains(query) || c.name.toLowerCase().contains(query)).toList();
    final followLogins = {for (final f in filteredFollows) f.login};
    final extraSearch = searchResults.where((c) => !followLogins.contains(c.login)).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: textEditingController,
              autocorrect: false,
              autofocus: false,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Search channels or type names, comma-separated', 'Поиск канала или ники через запятую'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: textEditingController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          textEditingController.clear();
                          _onQuery('');
                        },
                      ),
              ),
              onChanged: _onQuery,
              onSubmitted: (_) => _submitText(),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadFollows(force: true),
              child: ListView(
                children: [
                  if (followsError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(followsError!, style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  if (loadingFollows) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                  if (!loadingFollows && filteredFollows.isNotEmpty) _header(theme, query.isEmpty ? tr('Following (${follows.length}) · LIVE: ${follows.where((f) => f.live).length}', 'Мои подписки (${follows.length}) · LIVE: ${follows.where((f) => f.live).length}') : tr('Following', 'В подписках')),
                  for (final c in filteredFollows) _tile(theme, c),
                  if (query.isNotEmpty && (searching || extraSearch.isNotEmpty)) _header(theme, tr('Search Twitch', 'Поиск по Twitch')),
                  if (searching) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                  for (final c in extraSearch) _tile(theme, c),
                  if (query.isNotEmpty && !searching && filteredFollows.isEmpty && extraSearch.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(tr('Add \'$query\'', 'Добавить «$query»')),
                      subtitle: Text(tr('Nothing found — join by name directly', 'Ничего не найдено — подключиться по нику напрямую')),
                      onTap: _submitText,
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(selected.isEmpty ? (query.isEmpty ? tr('Select channels', 'Отметьте каналы') : tr('Add \'$query\'', 'Добавить «$query»')) : tr('Add (${selected.length})', 'Добавить (${selected.length})')),
                  onPressed: selected.isEmpty && query.isEmpty ? null : _submitText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
      );

  Widget _tile(ThemeData theme, _Ch c) {
    final joined = _joined(c.login);
    final isSel = selected.contains(c.login);
    final sub = [
      if (c.live) '🔴 ${c.viewers != null ? '${c.viewers} · ' : ''}${c.game ?? 'LIVE'}',
      if (!c.live && c.followed && joined) tr('already open', 'уже открыт'),
      if (!c.followed && !c.live) tr('offline', 'оффлайн'),
    ].join();
    return ListTile(
      dense: true,
      enabled: !joined,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: c.avatar != null ? NetworkImageW(c.avatar!, fit: BoxFit.cover) : Container(color: theme.dividerColor, child: const Icon(Icons.person, size: 20)),
            ),
          ),
          if (c.live)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: theme.canvasColor, width: 2))),
            ),
        ],
      ),
      title: Text(c.name.toLowerCase() == c.login ? c.name : '${c.name} (${c.login})', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: sub.isEmpty && c.title == null ? null : Text(c.live && c.title != null ? '$sub — ${c.title}' : sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: joined
          ? const Icon(Icons.check, size: 20)
          : IconButton(
              tooltip: tr('Add now', 'Добавить сразу'),
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _join([c.login, ...selected]),
            ),
      onTap: joined
          ? null
          : () => setState(() {
                if (!selected.remove(c.login)) selected.add(c.login);
              }),
      selected: isSel,
      selectedTileColor: theme.colorScheme.primary.withAlpha(30),
    );
  }
}

class _ScopeError implements Exception {
  final String message;
  _ScopeError(this.message);
  @override
  String toString() => message;
}
