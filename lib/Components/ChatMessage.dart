import 'package:cached_network_image/cached_network_image.dart';
import '../Badges/Chatsen2Badges.dart';
import '/Badges/BTTVBadges.dart';
import '/Badges/ChatsenBadges.dart';
import '/Badges/ChatterinoBadges.dart';
import '/Badges/ChattyBadges.dart';
import '/Badges/DankChatBadges.dart';
import '/Badges/FFZAPBadges.dart';
import '/Badges/FFZBadges.dart';
import '/Badges/SevenTVBadges.dart';
import '/Components/WidgetTooltip.dart';
import '/Settings/Settings.dart';
import '/Settings/SettingsState.dart';
import 'package:flutter/gestures.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;
import 'package:flutter_svg/svg.dart';
import '../Consts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' as ui;
import 'dart:async';

import 'ChatInputBox.dart';
import 'UserCard.dart';
import 'EmotePopup.dart';
import 'UserPrefs.dart';
import 'MediaPreview.dart';
import 'ReplyThread.dart';
import 'UI/NetworkImageWrapper.dart';

/// [ChatMessage] is a Widget that takes a [twitch.Message] and renders into something readable and interactable.
class ChatMessage extends StatelessWidget {
  final String? prefixText;
  final twitch.Message message;
  final Color? backgroundColor;
  final bool shadow;
  final GlobalKey<ChatInputBoxState>? gkey;

  /// Внутри окна ветки шапка ответа и счётчик ответов не нужны.
  final bool inThread;

  const ChatMessage({
    Key? key,
    this.prefixText,
    required this.message,
    this.backgroundColor,
    this.shadow = false,
    this.gkey,
    this.inThread = false,
  }) : super(key: key);

  /// Сколько ответов в чате ссылается на это сообщение как на корень ветки.
  int get replyCount {
    final id = message.id;
    if (id == null) return 0;
    return message.channel?.messages.where((m) => m.threadId == id).length ?? 0;
  }

  /// 15 стандартных цветов Twitch для юзеров, не выбравших цвет (как в Chatterino).
  static const _twitchDefaults = [
    0xFFFF0000, 0xFF0000FF, 0xFF008000, 0xFFB22222, 0xFFFF7F50, 0xFF9ACD32, 0xFFFF4500, 0xFF2E8B57,
    0xFFDAA520, 0xFFD2691E, 0xFF5F9EA0, 0xFF1E90FF, 0xFFFF69B4, 0xFF8A2BE2, 0xFF00FF7F,
  ];

  static Color nickColor(String? hex, String? login) {
    final v = hex == null ? null : int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
    final name = (login ?? '').toLowerCase();
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return Color(_twitchDefaults[h % _twitchDefaults.length]);
  }

  /// Цвет любого юзера в этом чате (для @упоминаний «цветом ника»).
  Color colorForLogin(BuildContext context, String login) {
    final custom = UserPrefs.instance.userColor(login);
    if (custom != null) return custom;
    final last = message.channel?.messages.lastWhereOrNull((m) => m.user?.login?.toLowerCase() == login.toLowerCase());
    return getUserColor(context, nickColor(last?.user?.color, login));
  }

  /// Фильтр значков по настройке «Значки у ника».
  static const _roleBadges = ['broadcaster', 'moderator', 'lead_moderator', 'vip', 'subscriber', 'founder', 'staff', 'admin', 'global_mod', 'partner'];

  Iterable<T> _filterBadges<T>(List<T> all) {
    switch (UserPrefs.instance.badgeMode) {
      case 2:
        return <T>[];
      case 1:
        return all.where((b) {
          final tag = '${(b as dynamic).tag ?? ''}';
          return _roleBadges.any((r) => tag.startsWith('$r/'));
        });
      default:
        return all;
    }
  }

  /// Стилизованное @упоминание по настройке «Стиль упоминаний».
  InlineSpan _mentionSpan(BuildContext context, String word, String login, List<Shadow>? shadows) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    void open() => UserCard.show(context, login: login, channel: message.channel);
    switch (UserPrefs.instance.mentionStyle) {
      case 0: // обычный
        return TextSpan(text: '$word ', style: TextStyle(fontWeight: FontWeight.bold, shadows: shadows), recognizer: TapGestureRecognizer()..onTap = open);
      case 2: // плашка
      case 3: // рамка
        final pill = UserPrefs.instance.mentionStyle == 2;
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: open,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: pill ? accent.withAlpha(50) : null,
                  border: pill ? null : Border.all(color: accent, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(word, style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        );
      case 4: // цвет ника
        return TextSpan(text: '$word ', style: TextStyle(color: colorForLogin(context, login), fontWeight: FontWeight.bold, shadows: shadows), recognizer: TapGestureRecognizer()..onTap = open);
      default: // 1 — акцент
        return TextSpan(text: '$word ', style: TextStyle(color: accent, fontWeight: FontWeight.bold, shadows: shadows), recognizer: TapGestureRecognizer()..onTap = open);
    }
  }

  /// Шапка ответа: «↪ @ник: текст родителя». Тап — открыть ветку.
  Widget _replyHeader(BuildContext context) {
    final theme = Theme.of(context);
    final name = message.replyParentName ?? '';
    final body = message.replyParentBody ?? '';
    return InkWell(
      onTap: () => ReplyThread.show(context, message: message, input: gkey?.currentState),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Icon(Icons.subdirectory_arrow_right, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '@$name ',
                    style: TextStyle(color: colorForLogin(context, message.replyParentLogin ?? name), fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: body),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color getUserColor(BuildContext context, Color color) {
    switch (Theme.of(context).brightness) {
      case Brightness.dark:
        final hsl = HSLColor.fromColor(Color(color.value == 0xFF000000 ? 0xFF010101 : color.value));
        return hsl.withLightness(hsl.lightness.clamp(0.6, 1.0)).toColor();
      case Brightness.light:
        final hsl = HSLColor.fromColor(Color(color.value == 0xFF000000 ? 0xFF010101 : color.value));
        return hsl.withLightness(hsl.lightness.clamp(0.0, 0.4)).toColor();
    }
  }

  Future<ui.Image> imageFromUrl(String url) {
    var completer = Completer<ui.Image>();
    NetworkImage(url).resolve(ImageConfiguration()).addListener(ImageStreamListener((image, synchronousCall) {
      completer.complete(image.image);
    }));
    return completer.future;
  }

  Future<void> _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(label)));
  }

  Future<void> _showActions(BuildContext context) async {
    final login = message.user?.login;
    final ts = message.dateTime == null ? '' : '${message.dateTime!.hour.toString().padLeft(2, '0')}:${message.dateTime!.minute.toString().padLeft(2, '0')} ';
    final input = gkey?.currentState ?? (message.channel != null ? ChatInputBoxState.of(message.channel!) : null);
    await showChatsenSheet(
      context,
      (sheet) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (login != null)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(tr('Profile: $login', 'Профиль $login')),
                onTap: () {
                  Navigator.of(sheet).pop();
                  UserCard.show(context, login: login, channel: message.channel);
                },
              ),
            if (login != null && input != null && message.id != null)
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text(tr('Reply', 'Ответить')),
                subtitle: Text(tr('Twitch reply — linked to this message', 'Ответ Twitch — привязан к этому сообщению')),
                onTap: () {
                  Navigator.of(sheet).pop();
                  input.startReply(message);
                },
              ),
            if (message.threadId != null || replyCount > 0)
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: Text(tr('Open thread', 'Открыть ветку')),
                onTap: () {
                  Navigator.of(sheet).pop();
                  ReplyThread.show(context, message: message, input: input);
                },
              ),
            if (login != null && input != null)
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: Text(tr('Mention (@username)', 'Упомянуть (@ник)')),
                onTap: () {
                  Navigator.of(sheet).pop();
                  input.insertMention(login);
                },
              ),
            if (login != null)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(tr('Copy username', 'Копировать ник')),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _copy(context, login, tr('Username copied', 'Ник скопирован'));
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(tr('Copy message', 'Копировать сообщение')),
              onTap: () {
                Navigator.of(sheet).pop();
                _copy(context, message.body ?? '', tr('Message copied', 'Сообщение скопировано'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all),
              title: Text(tr('Copy with username and time', 'Копировать с ником и временем')),
              onTap: () {
                Navigator.of(sheet).pop();
                _copy(context, '$ts${message.user?.displayName ?? ''}: ${message.body ?? ''}', tr('Copied', 'Скопировано'));
              },
            ),
            if (input != null)
              ListTile(
                leading: const Icon(Icons.content_paste_go),
                title: Text(tr('Paste into input', 'Вставить текст в поле ввода')),
                onTap: () {
                  Navigator.of(sheet).pop();
                  input.appendText(message.body ?? '');
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Свёрнутая строка для сообщения из игнора: тап раскрывает/сворачивает обратно.
  Widget _ignoredStub(BuildContext context) {
    final theme = Theme.of(context);
    final login = message.user?.login ?? '';
    final name = UserPrefs.instance.aliasOf(login) ?? message.user?.displayName ?? login;
    final ts = message.dateTime == null ? '' : '${message.dateTime!.hour.toString().padLeft(2, '0')}:${message.dateTime!.minute.toString().padLeft(2, '0')} ';
    return Container(
      key: ValueKey(message.id),
      width: double.infinity,
      color: backgroundColor,
      child: InkWell(
        onTap: () => UserPrefs.instance.toggleRevealed(message.id),
        onLongPress: () => _showActions(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
          child: Text(
            tr('$ts$name: hidden (ignored) — tap to show', '$ts$name: скрыто (игнор) — тап, чтобы показать'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withAlpha(90), fontStyle: FontStyle.italic),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = UserPrefs.instance;
    if (prefs.isIgnored(message.user?.login) && !prefs.revealed.contains(message.id)) {
      return _ignoredStub(context);
    }
    // DearKing mod: свой цвет из карточки юзера > цвет из Twitch > стандартная палитра Twitch по нику
    // (раньше юзеры без выбранного цвета были серыми 777777)
    var color = UserPrefs.instance.userColor(message.user?.login) ?? getUserColor(context, nickColor(message.user?.color, message.user?.login));
    var spans = <InlineSpan>[];
    // ссылки, под которыми показываем превью медиа
    final previews = <String>[];
    var shadowSpread = 1.0;
    var shadowColor = Theme.of(context).colorScheme.surface;
    var shadows = shadow
        ? [
            Shadow(offset: Offset(-shadowSpread, -shadowSpread), color: shadowColor),
            Shadow(offset: Offset(shadowSpread, -shadowSpread), color: shadowColor),
            Shadow(offset: Offset(shadowSpread, shadowSpread), color: shadowColor),
            Shadow(offset: Offset(-shadowSpread, shadowSpread), color: shadowColor),
          ]
        : null;

    for (var token in message.tokens) {
      switch (token.type) {
        case twitch.MessageTokenType.Text:
          // Библиотека склеивает соседние слова в один токен («@ник [дата] текст»),
          // поэтому упоминания ищем по словам, а обычные слова собираем обратно в один кусок.
          final plainStyle = TextStyle(color: (message.user == null || message.action) ? color : null, shadows: shadows);
          final buffer = StringBuffer();
          void flush() {
            if (buffer.isEmpty) return;
            spans.add(TextSpan(text: buffer.toString(), style: plainStyle));
            buffer.clear();
          }

          final words = '${token.data}'.split(' ');
          for (var w = 0; w < words.length; w++) {
            final word = words[w];
            final mention = RegExp(r'^@([A-Za-z0-9_]{2,25})[,.:!?]*$').firstMatch(word);
            if (mention == null) {
              buffer.write('$word ');
              continue;
            }
            // в ответе Twitch сам ставит «@ник» первым словом — он уже показан в шапке ответа
            final isFirstWord = identical(token, message.tokens.first) && w == 0;
            if (isFirstWord && message.replyParentLogin != null && mention.group(1)!.toLowerCase() == message.replyParentLogin!.toLowerCase()) {
              continue;
            }
            flush();
            spans.add(_mentionSpan(context, word, mention.group(1)!, shadows));
          }
          flush();
          break;
        // DearKing mod: ссылка всегда остаётся текстом (тап — открыть, удержание — меню сообщения),
        // а под ней, если включено «Превью медиа», — картинка/GIF/видео или карточка страницы.
        case twitch.MessageTokenType.Link:
        case twitch.MessageTokenType.Image:
        case twitch.MessageTokenType.Video:
          final linkUrl = '${token.data}';
          spans.add(
            TextSpan(
              children: [
                TextSpan(
                  text: linkUrl,
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                    shadows: shadows,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(linkUrl), mode: LaunchMode.externalApplication),
                ),
                TextSpan(text: ' '),
              ],
            ),
          );
          if ((BlocProvider.of<Settings>(context).state as SettingsLoaded).messageImagePreview) {
            previews.add(linkUrl);
          }
          break;
        case twitch.MessageTokenType.Emote:
          if (!kUnverifiedVersion) {
            spans.add(
              WidgetSpan(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WidgetTooltip(
                      message: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: NetworkImageW(
                                (token.data as twitch.Emote).mipmap!.last!,
                                height: 96.0,
                              ),
                            ),
                            Text((token.data as twitch.Emote).name!),
                            Text((token.data as twitch.Emote).provider!),
                          ],
                        ),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => EmotePopup.show(context, emotes: [token.data as twitch.Emote], channel: message.channel, input: gkey?.currentState),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: NetworkImageW(
                            token.data.provider == 'Twitch' ? token.data.mipmap[1] : token.data.mipmap.last,
                            scale: token.data.provider == 'Twitch' ? 2.0 : (token.data.mipmap.length == 1 ? 1.0 : 4.0),
                            height: token.data.provider == 'Emoji' ? 24.0 : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            spans.add(
              TextSpan(
                text: '${(token.data as twitch.Emote).name!} ',
                style: TextStyle(
                  color: (message.user == null || message.action) ? color : null,
                  shadows: shadows,
                ),
              ),
            );
          }
          break;
        case twitch.MessageTokenType.EmoteStack:
          spans.add(
            WidgetSpan(
              child: WidgetTooltip(
                message: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        // child: ,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            for (var emote in token.data)
                              NetworkImageW(
                                emote.mipmap!.last!,
                                height: 96.0,
                                fit: BoxFit.fitHeight,
                              ),
                            // Padding(
                            //   padding: const EdgeInsets.only(right: 4.0),
                            //   // child: NetworkImageW(
                            //   //   emote.provider == 'Twitch' ? emote.mipmap[1] : emote.mipmap.last,
                            //   //   scale: emote.provider == 'Twitch' ? 2.0 : 4.0,
                            //   //   height: emote.provider == 'Emoji' ? 24.0 : null,
                            //   // ),
                            // ),
                          ],
                        ),
                      ),
                      Text((token.data as List<twitch.Emote>).first.name!),
                      Text((token.data as List<twitch.Emote>).first.provider!),
                      for (var emote in (token.data as List<twitch.Emote>))
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: NetworkImageW(emote.mipmap!.first!),
                              ),
                              Text(emote.name!),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => EmotePopup.show(context, emotes: List<twitch.Emote>.from(token.data), channel: message.channel, input: gkey?.currentState),
                  child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var emote in token.data)
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: NetworkImageW(
                          emote.provider == 'Twitch' ? emote.mipmap[1] : emote.mipmap.last,
                          scale: emote.provider == 'Twitch' ? 2.0 : 4.0,
                          height: emote.provider == 'Emoji' ? 24.0 : null,
                        ),
                      ),
                  ],
                ),
                ),
              ),
            ),
          );
          break;
        case twitch.MessageTokenType.User:
          break;
      }
    }

    return Opacity(
      opacity: (message.history ? 0.5 : 1.0) * (message.deleted ? 0.25 : 1.0),
      // child: Dismissible(
      //   background: Container(
      //     color: Colors.deepOrange,
      //     child: Align(
      //       alignment: Alignment.centerLeft,
      //       child: Padding(
      //         padding: const EdgeInsets.only(left: 8.0),
      //         child: Icon(
      //           Icons.alternate_email,
      //           size: 16.0,
      //         ),
      //       ),
      //     ),
      //   ),
      //   secondaryBackground: Container(
      //     color: Colors.deepPurple,
      //     child: Align(
      //       alignment: Alignment.centerRight,
      //       child: Padding(
      //         padding: const EdgeInsets.only(right: 8.0),
      //         child: Icon(
      //           Icons.copy,
      //           size: 16.0,
      //         ),
      //       ),
      //     ),
      //   ),
      //   confirmDismiss: (d) async {
      //     // ChatInputBox.appendText(context, 'test');
      //     if (d == DismissDirection.startToEnd) {
      //       gkey?.currentState?.appendText('@${message.user?.login ?? 'twitch'} ');
      //     } else if (d == DismissDirection.endToStart) {
      //       gkey?.currentState?.appendText(message.body!);
      //       await Clipboard.setData(ClipboardData(text: message.body ?? ''));
      //       // ScaffoldMessenger.of(context).showSnackBar(
      //       //   SnackBar(
      //       //     behavior: SnackBarBehavior.floating,
      //       //     content: Text('Text copied to clipboard!'),
      //       //   ),
      //       // );
      //     }
      //     return false;
      //   },
      key: ValueKey(message.id),
      child: Container(
        width: double.infinity,
        color: message.mention ? Theme.of(context).colorScheme.primary.withAlpha(48) : backgroundColor,
        child: InkWell(
          // Двойной тап убран: он держал gesture arena ~300 мс и «съедал»
          // одиночные тапы по нику. Удержание теперь открывает меню действий.
          onLongPress: () => _showActions(context),
          // раскрытое сообщение из игнора сворачивается обратно тапом
          onTap: UserPrefs.instance.isIgnored(message.user?.login) ? () => UserPrefs.instance.toggleRevealed(message.id) : null,
          // onLongPress: () async => await Clipboard.setData(ClipboardData(text: message.body ?? '')),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // DearKing mod: шапка ответа «↪ @ник: текст» — тап открывает ветку
                if (!inThread && message.replyParentId != null) _replyHeader(context),
                Text.rich(
              TextSpan(
                children: <InlineSpan>[
                      if (prefixText != null)
                        TextSpan(
                          text: '$prefixText ',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            shadows: shadows,
                          ),
                        ),
                      if ((BlocProvider.of<Settings>(context).state as SettingsLoaded).messageTimestamp)
                        TextSpan(
                          text: '${message.dateTime!.hour.toString().padLeft(2, '0')}:${message.dateTime!.minute.toString().padLeft(2, '0')} ',
                          style: TextStyle(
                            // fontWeight: FontWeight.bold,
                            shadows: shadows,
                            color: Colors.grey[400],
                          ),
                        ),
                      // if (first != null)
                      //   for (var badge in first.badges)
                      //     WidgetSpan(
                      //       child: Padding(
                      //         padding: const EdgeInsets.only(right: 4.0),
                      //         child: NetworkImageW(
                      //           data!.badges.firstWhere((element) => element.name == badge.badgeName).image,
                      //           height: 18.0,
                      //         ),
                      //       ),
                      //     ),
                      if (message.user != null)
                        // Good god chatsen2 will need something better than this
                        for (var badge in _filterBadges([
                          ...message.badges,
                          ...BlocProvider.of<BTTVBadges>(context).getBadgesForUser('${message.user?.id}'),
                          ...BlocProvider.of<FFZBadges>(context).getBadgesForUser('${message.user?.login?.toLowerCase()}'),
                          ...BlocProvider.of<FFZAPBadges>(context).getBadgesForUser('${message.user?.id}'),
                          ...BlocProvider.of<ChatterinoBadges>(context).getBadgesForUser('${message.user?.id}'),
                          ...BlocProvider.of<DankChatBadges>(context).getBadgesForUser('${message.user?.id}'),
                          ...BlocProvider.of<ChattyBadges>(context).getBadgesForUser('${message.user?.login}'),
                          ...BlocProvider.of<SevenTVBadges>(context).getBadgesForUser('${message.user?.id}'),
                          ...BlocProvider.of<ChatsenBadges>(context).getBadgesForUser('${message.user?.id}'),
                          ...BlocProvider.of<Chatsen2Badges>(context).getBadgesForUser('${message.user?.id}'),
                        ]))
                          WidgetSpan(
                            child: WidgetTooltip(
                              message: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4.0),
                                      child: ClipRRect(
                                        borderRadius: badge.color != null ? BorderRadius.circular(96.0 / 8.0) : BorderRadius.zero,
                                        child: Container(
                                          color: badge.color != null ? Color(int.tryParse(badge.color ?? '777777', radix: 16) ?? 0x777777).withAlpha(255) : null,
                                          child: badge.mipmap!.last!.endsWith('.svg')
                                              ? SvgPicture.network(
                                                  badge.mipmap!.last!,
                                                  height: 96.0,
                                                  fit: BoxFit.fitHeight,
                                                )
                                              : NetworkImageW(
                                                  badge.mipmap!.last!,
                                                  height: 96.0,
                                                  fit: BoxFit.fitHeight,
                                                  cache: badge.cache,
                                                ),
                                        ),
                                      ),
                                    ),
                                    Text('${badge.title}'),
                                    if (badge.title != badge.description && badge.description != null) Text('${badge.description}'),
                                  ],
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4.0),
                                child: ClipRRect(
                                  borderRadius: badge.color != null ? BorderRadius.circular(2.0) : BorderRadius.zero,
                                  child: Container(
                                    color: badge.color != null ? Color(int.tryParse(badge.color ?? '777777', radix: 16) ?? 0x777777).withAlpha(255) : null,
                                    child: badge.mipmap!.last!.endsWith('.svg')
                                        ? SvgPicture.network(
                                            badge.mipmap!.last!,
                                            height: 18.0,
                                          )
                                        : NetworkImageW(
                                            badge.mipmap!.last!,
                                            height: 18.0,
                                            fit: BoxFit.fitHeight,
                                            cache: badge.cache,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      if (message.user != null)
                        TextSpan(
                          // локальное имя (Rename) показываем вместо ника, оригинальный логин — в скобках
                          text: (UserPrefs.instance.aliasOf(message.user!.login) != null
                                  ? '${UserPrefs.instance.aliasOf(message.user!.login)} (${message.user!.login})'
                                  : '${message.user!.displayName}' + (message.user!.displayName!.toLowerCase() != message.user!.login!.toLowerCase() ? ' (${message.user!.login})' : '')) +
                              (message.action ? ' ' : ': '),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            shadows: shadows,
                          ),
                          recognizer: TapGestureRecognizer()..onTap = () => UserCard.show(context, login: message.user!.login!, channel: message.channel),
                        ),
                    ] +
                    spans,
              ),
            ),
                for (final url in previews) MediaPreview(key: ValueKey(url), url: url),
                // у сообщения есть ответы — кнопка «💬 N ответов» открывает ветку
                if (!inThread && replyCount > 0)
                  InkWell(
                    onTap: () => ReplyThread.show(context, message: message, input: gkey?.currentState),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, size: 15, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            tr('$replyCount replies', 'Ответов: $replyCount'),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      // ),
    );
  }
}
