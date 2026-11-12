import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'ChatInputBox.dart';
import 'UI/NetworkImageWrapper.dart';
import 'UserPrefs.dart';

/// Попап эмоута по тапу: картинка, название, платформа, автор + Копировать / Вставить / Страница.
/// Для стека (zero-width эмоуты поверх базового) показывает каждый слой отдельной строкой.
class EmotePopup extends StatefulWidget {
  final List<twitch.Emote> emotes;
  final twitch.Channel? channel;
  final ChatInputBoxState? input;

  const EmotePopup({Key? key, required this.emotes, this.channel, this.input}) : super(key: key);

  static Future<void> show(BuildContext context, {required List<twitch.Emote> emotes, twitch.Channel? channel, ChatInputBoxState? input}) async {
    if (emotes.isEmpty) return;
    final inp = input ?? (channel != null ? ChatInputBoxState.of(channel) : null);
    await showChatsenSheet(context, (_) => EmotePopup(emotes: emotes, channel: channel, input: inp));
  }

  @override
  State<EmotePopup> createState() => _EmotePopupState();
}

class _EmoteMeta {
  final String? author;
  final String? extra; // тип/тир для Twitch, «zero-width» и т.п.
  const _EmoteMeta({this.author, this.extra});
}

class _EmotePopupState extends State<EmotePopup> {
  // Кэш метаданных между открытиями попапа: ключ provider:id
  static final Map<String, _EmoteMeta> _cache = {};
  final Map<String, Future<_EmoteMeta>> _futures = {};

  /// Сколько раз нажали «Вставить» с момента открытия (или последней отправки).
  int inserted = 0;

  /// Короткая подсветка «Отправлено ✓» на кнопке.
  bool sentFlash = false;

  static String _platformName(String? p) {
    switch (p) {
      case '7TV':
        return '7TV';
      case 'BTTV':
        return 'BetterTTV';
      case 'FFZ':
        return 'FrankerFaceZ';
      case 'Twitch':
        return 'Twitch';
      case 'Emoji':
        return 'Emoji';
      default:
        return p ?? '—';
    }
  }

  static Uri? _pageUrl(twitch.Emote e) {
    if (e.id == null || e.id!.isEmpty) return null;
    switch (e.provider) {
      case '7TV':
        return Uri.parse('https://7tv.app/emotes/${e.id}');
      case 'BTTV':
        return Uri.parse('https://betterttv.com/emotes/${e.id}');
      case 'FFZ':
        return Uri.parse('https://www.frankerfacez.com/emoticon/${e.id}');
      default:
        return null;
    }
  }

  Future<_EmoteMeta> _meta(twitch.Emote e) {
    final key = '${e.provider}:${e.id}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _futures[key] ??= _fetch(e).then((m) {
      _cache[key] = m;
      return m;
    });
  }

  Future<_EmoteMeta> _fetch(twitch.Emote e) async {
    final zw = e.zeroWidth ? tr('zero-width', 'наложение (zero-width)') : null;
    if (e.id == null || e.id!.isEmpty) return _EmoteMeta(extra: zw);
    try {
      switch (e.provider) {
        case '7TV':
          final j = jsonDecode(utf8.decode((await http.get(Uri.parse('https://7tv.io/v3/emotes/${e.id}'))).bodyBytes));
          return _EmoteMeta(author: j['owner']?['display_name'] ?? j['owner']?['username'], extra: zw);
        case 'BTTV':
          final j = jsonDecode((await http.get(Uri.parse('https://api.betterttv.net/3/emotes/${e.id}'))).body);
          return _EmoteMeta(author: j['user']?['displayName'] ?? j['user']?['name'], extra: zw);
        case 'FFZ':
          final j = jsonDecode((await http.get(Uri.parse('https://api.frankerfacez.com/v1/emote/${e.id}'))).body);
          return _EmoteMeta(author: j['emote']?['owner']?['display_name'] ?? j['emote']?['owner']?['name'], extra: zw);
        case 'Twitch':
          // Helix не отдаёт владельца по id эмоута, поэтому используем публичный api.ivr.fi
          final j = jsonDecode((await http.get(Uri.parse('https://api.ivr.fi/v2/twitch/emotes/${e.id}?id=true'))).body);
          final type = j['emoteType'] as String?;
          final tier = j['emoteTier'];
          final parts = [
            if (type != null) type.toLowerCase(),
            if (tier != null && '$tier'.isNotEmpty) tr('tier $tier', 'тир $tier'),
          ];
          return _EmoteMeta(author: j['channelName'] ?? (type == 'GLOBALS' ? tr('Twitch (global)', 'Twitch (глобальный)') : null), extra: parts.isEmpty ? null : parts.join(', '));
        default:
          return _EmoteMeta(extra: zw);
      }
    } catch (_) {
      return _EmoteMeta(extra: zw);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));

  String _code(twitch.Emote e) => e.alt ?? e.name ?? '';

  /// Отправить набранное в поле ввода; если там пусто — сам эмоут.
  void _send() {
    final input = widget.input!;
    if (!input.canSend) {
      _snack(tr('Log in to send messages', 'Войдите в аккаунт, чтобы писать в чат'));
      return;
    }
    final typed = input.textEditingController.text.trim();
    final fullCode = widget.emotes.map(_code).join(' ');
    if (typed.isEmpty) {
      input.send(fullCode, remove: false);
    } else {
      input.send(typed); // как Enter: команды работают, поле очищается
    }
    setState(() {
      inserted = 0;
      sentFlash = true;
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => sentFlash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final main = widget.emotes.first;
    // Для стека вставляем/копируем всю цепочку: «база zw1 zw2»
    final fullCode = widget.emotes.map(_code).join(' ');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              height: 112,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (final e in widget.emotes)
                    if (e.mipmap != null && e.mipmap!.isNotEmpty) NetworkImageW(e.mipmap!.last!, height: 112, fit: BoxFit.fitHeight) else Text(_code(e), style: const TextStyle(fontSize: 72)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final e in widget.emotes) _infoRow(theme, e, showThumb: widget.emotes.length > 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.copy,
                  label: tr('Copy', 'Копировать'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: fullCode));
                    _snack(tr("'$fullCode' copied", '«$fullCode» скопировано'));
                  },
                ),
              ),
              if (widget.input != null)
                Expanded(
                  child: ChatsenActionButton(
                    icon: Icons.content_paste_go,
                    label: tr('Insert', 'Вставить'),
                    // оранжевый счётчик вставок
                    badge: inserted > 0 ? inserted : null,
                    onTap: () {
                      // попап остаётся открытым, клавиатура не выезжает — можно жать несколько раз
                      widget.input!.insertText(fullCode, focus: false);
                      setState(() => inserted++);
                    },
                  ),
                ),
              if (widget.input != null)
                Expanded(
                  child: ChatsenActionButton(
                    icon: sentFlash ? Icons.check : Icons.send,
                    label: sentFlash ? tr('Sent', 'Готово') : tr('Send', 'Отправить'),
                    active: sentFlash,
                    onTap: _send,
                  ),
                ),
              if (_pageUrl(main) != null)
                Expanded(
                  child: _ActionButton(
                    icon: Icons.open_in_new,
                    label: tr('Page', 'Страница'),
                    onTap: () => launchUrl(_pageUrl(main)!, mode: LaunchMode.externalApplication),
                  ),
                ),
            ],
          ),
          if (widget.input != null && widget.input!.textEditingController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            // что уйдёт в чат по «Отправить»
            Text(
              widget.input!.textEditingController.text.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(ThemeData theme, twitch.Emote e, {required bool showThumb}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showThumb && e.mipmap != null && e.mipmap!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(right: 12, top: 2), child: NetworkImageW(e.mipmap!.first!, height: 28)),
          Expanded(
            child: FutureBuilder<_EmoteMeta>(
              future: _meta(e),
              builder: (context, snap) {
                final m = snap.data;
                final loading = snap.connectionState != ConnectionState.done;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(_code(e), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text(tr('Platform: ${_platformName(e.provider)}', 'Платформа: ${_platformName(e.provider)}'), style: theme.textTheme.bodyMedium),
                    Text(
                      tr('Author: ', 'Автор: ') + (m?.author ?? (loading ? '…' : '—')),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (m?.extra != null) Text(m!.extra!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Компактная кнопка «иконка над подписью» — общая для попапа эмоута и карточки юзера.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ChatsenActionButton(icon: icon, label: label, onTap: onTap);
}

class ChatsenActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;

  /// Число в оранжевом кружке в углу кнопки (null — без значка).
  final int? badge;

  const ChatsenActionButton({Key? key, required this.icon, required this.label, required this.onTap, this.color, this.active = false, this.badge}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? (active ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface);
    final button = Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: active ? theme.colorScheme.primary : theme.colorScheme.onSurface.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
    if (badge == null) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 22),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Text('$badge', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}
