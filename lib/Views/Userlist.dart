import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/Components/ChatMessage.dart';
import '/Components/UserCard.dart';
import '/Components/UserPrefs.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;

/// The [UserlistView] class is a view designed to hold the list of users currently connected to a channel. It can be refreshed with a pull-to-refresh swipe movement.
class UserlistView extends StatefulWidget {
  final twitch.Channel? channel;

  const UserlistView({
    Key? key,
    required this.channel,
  }) : super(key: key);

  @override
  _UserlistViewState createState() => _UserlistViewState();
}

class _UserlistViewState extends State<UserlistView> {
  Future<dynamic>? gqlFuture;
  TextEditingController tec = TextEditingController();

  void refreshUserlist() async => gqlFuture = widget.channel!.updateUsers();

  @override
  void initState() {
    refreshUserlist();
    super.initState();
  }

  @override
  void dispose() {
    tec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: gqlFuture,
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
          if (snapshot.hasData) {
            var userlistWidgets = <Widget>[];
            final theme = Theme.of(context);
            final fontSize = UserPrefs.instance.chatFontSize + 3; // в списке чуть крупнее, чем в чате
            // цвет ника из последних сообщений канала (один проход по списку)
            final seen = <String, String?>{};
            for (final m in widget.channel!.messages.reversed) {
              final login = m.user?.login?.toLowerCase();
              if (login != null && !seen.containsKey(login)) seen[login] = m.user?.color;
            }
            Color colorOf(String user) => ChatMessage.readable(
                  theme.brightness,
                  UserPrefs.instance.userColor(user) ?? ChatMessage.nickColor(seen[user.toLowerCase()], user),
                );
            // полупрозрачная обводка: на тёмной теме — тёмная, на светлой — светлая
            final outline = theme.brightness == Brightness.dark ? Colors.black.withAlpha(130) : Colors.white.withAlpha(170);
            for (var group in widget.channel!.users.entries) {
              if (group.value.isEmpty || !group.value.any((x) => x.toLowerCase().contains(tec.text.toLowerCase()))) continue;

              userlistWidgets.add(
                Padding(
                  padding: const EdgeInsets.only(left: 10.0, top: 12.0),
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              );

              for (var user in group.value.where((x) => x.toLowerCase().contains(tec.text.toLowerCase()))) {
                userlistWidgets.add(
                  InkWell(
                    // Раньше onTap был пустой — теперь открывает карточку профиля.
                    onTap: () => UserCard.show(context, login: user, channel: widget.channel),
                    onLongPress: () async {
                      await Clipboard.setData(ClipboardData(text: user));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('Username \'$user\' copied', 'Ник «$user» скопирован'))));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5.0),
                      child: _OutlinedNick(
                        name: UserPrefs.instance.aliasOf(user) ?? user,
                        login: UserPrefs.instance.aliasOf(user) != null ? user : null,
                        fontSize: fontSize,
                        color: UserPrefs.instance.isIgnored(user) ? theme.disabledColor : colorOf(user),
                        outline: outline,
                        italic: UserPrefs.instance.isIgnored(user),
                      ),
                    ),
                  ),
                );
              }
            }

            return RefreshIndicator(
              onRefresh: () async => refreshUserlist(),
              child: Column(
                children: [
                  TextField(
                    controller: tec,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                      filled: false,
                      isDense: true,
                      hintText: tr('Search usernames', 'Поиск по никам'),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() {}),
                    // onSubmitted: (text) async => submit(),
                  ),
                  Expanded(
                    child: ListView(
                      children: userlistWidgets,
                    ),
                  ),
                ],
              ),
            );
          }
          return Center(child: CircularProgressIndicator.adaptive());
        },
      );
}

/// Ник в списке зрителей: свой цвет + полупрозрачная обводка (два слоя текста).
class _OutlinedNick extends StatelessWidget {
  final String name;
  final String? login; // оригинальный логин, если показан псевдоним
  final double fontSize;
  final Color color;
  final Color outline;
  final bool italic;

  const _OutlinedNick({required this.name, this.login, required this.fontSize, required this.color, required this.outline, this.italic = false});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
    final stroke = base.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (fontSize / 6).clamp(2.0, 4.5)
        ..strokeJoin = StrokeJoin.round
        ..color = outline,
    );
    final suffix = login != null ? '  ($login)' : '';
    final suffixStyle = TextStyle(fontSize: fontSize * 0.7, fontWeight: FontWeight.w500, color: Theme.of(context).hintColor);
    // нижний слой — обводка, верхний — цветной ник (+ логин, если показан псевдоним)
    return Stack(
      children: [
        Text(name, style: stroke, maxLines: 1, overflow: TextOverflow.clip),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: name, style: base.copyWith(color: color)),
            if (suffix.isNotEmpty) TextSpan(text: suffix, style: suffixStyle),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
