import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;

import '../Consts.dart';
import '/Components/EmotePopup.dart';
import '/Components/UI/WidgetBlur.dart';
import '/Components/UserPrefs.dart';

/// Окно эмоутов (DearKing mod).
///
/// Раньше группы рисовались через GridView(shrinkWrap) внутри ListView — это создаёт и грузит
/// ВСЕ эмоуты канала сразу (сотни картинок в 4x), отсюда тормоза при открытии.
/// Теперь: ленивые слайверы (рисуются только видимые), картинки 2x с декодированием до 64 px,
/// сворачиваемые группы с запоминанием, кнопки ▲▼ для листания.
class EmoteListModal extends StatefulWidget {
  final twitch.Client? client;
  final twitch.Channel? channel;
  final Function(String? emote) insertEmote;

  const EmoteListModal({
    Key? key,
    required this.client,
    required this.channel,
    required this.insertEmote,
  }) : super(key: key);

  @override
  _EmoteListModalState createState() => _EmoteListModalState();
}

class _Section {
  final String key;
  final String title;
  final List<twitch.Emote> emotes;
  const _Section(this.key, this.title, this.emotes);
}

class _EmoteListModalState extends State<EmoteListModal> {
  final textEditingController = TextEditingController();

  String get query => textEditingController.text.trim().toLowerCase();

  @override
  void dispose() {
    textEditingController.dispose();
    super.dispose();
  }

  bool _match(twitch.Emote e) => query.isEmpty || (e.name ?? '').toLowerCase().contains(query);

  List<_Section> _byProvider(String tab, List<twitch.Emote> emotes) => [
        for (final g in groupBy(emotes, (twitch.Emote e) => e.provider ?? '?').entries) _Section('$tab:${g.key}', g.key, g.value),
      ];

  static String _emojiTitle(String c) {
    const ru = {
      'Smileys & Emotion': 'Смайлы и эмоции',
      'People & Body': 'Люди и тело',
      'Animals & Nature': 'Животные и природа',
      'Food & Drink': 'Еда и напитки',
      'Travel & Places': 'Путешествия и места',
      'Activities': 'Занятия',
      'Objects': 'Предметы',
      'Symbols': 'Символы',
      'Flags': 'Флаги',
    };
    return tr(c, ru[c] ?? c);
  }

  List<_Section> _emojiSections() => [
        for (final g in groupBy(widget.client!.emojis, (twitch.Emote e) => e.category ?? 'Other').entries)
          _Section('emoji:${g.key}', _emojiTitle(g.key), g.value),
      ];

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: kUnverifiedVersion ? 1 : 4,
        child: Builder(builder: (context) {
          return WidgetBlur(
            child: Material(
              color: Theme.of(context).canvasColor.withAlpha(UserPrefs.instance.panelAlpha(196)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(height: 1.0, color: Theme.of(context).dividerColor),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(width: 32.0, height: 2.0, color: Theme.of(context).dividerColor),
                  ),
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height / 2.6,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 32.0,
                          child: TabBar(
                            indicatorPadding: EdgeInsets.zero,
                            tabs: [
                              if (!kUnverifiedVersion) Tab(text: tr('Channel', 'Канал')),
                              if (!kUnverifiedVersion) const Tab(text: 'Twitch'),
                              if (!kUnverifiedVersion) Tab(text: tr('Global', 'Глобальные')),
                              Tab(text: tr('Emojis', 'Эмодзи')),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              if (!kUnverifiedVersion) _EmoteSections(sections: _byProvider('channel', widget.channel!.emotes), match: _match, query: query, onPick: _pick, onLongPress: _info),
                              if (!kUnverifiedVersion)
                                _EmoteSections(
                                  sections: [_Section('twitch:all', 'Twitch', widget.channel?.transmitter?.emotes ?? const [])],
                                  match: _match,
                                  query: query,
                                  onPick: _pick,
                                  onLongPress: _info,
                                ),
                              if (!kUnverifiedVersion) _EmoteSections(sections: _byProvider('global', widget.client!.emotes), match: _match, query: query, onPick: _pick, onLongPress: _info),
                              _EmoteSections(sections: _emojiSections(), match: _match, query: query, onPick: _pick, onLongPress: _info),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 48.0,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => setState(() {}),
                          enableFeedback: false,
                        ),
                        Expanded(
                          child: TextField(
                            controller: textEditingController,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 0.0),
                              filled: false,
                              isDense: true,
                              hintText: tr('Search emotes', 'Поиск эмоутов'),
                              border: InputBorder.none,
                            ),
                            onChanged: (text) => setState(() {}),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () async {
                            await widget.client?.updateEmotes();
                            await widget.client?.updateBadges();
                            await widget.channel?.updateEmotes();
                            await widget.channel?.updateBadges();
                            await widget.channel?.transmitter?.updateUserEmotes();
                            if (mounted) setState(() {});
                          },
                          tooltip: tr('Refresh emotes', 'Обновить эмоуты'),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1.0, color: Theme.of(context).dividerColor),
                ],
              ),
            ),
          );
        }),
      );

  void _pick(twitch.Emote e) => widget.insertEmote(e.alt ?? e.name);

  void _info(twitch.Emote e) => EmotePopup.show(context, emotes: [e], channel: widget.channel);
}

/// Список групп эмоутов: ленивые сетки, сворачиваемые заголовки, кнопки ▲▼.
class _EmoteSections extends StatefulWidget {
  final List<_Section> sections;
  final bool Function(twitch.Emote) match;
  final String query;
  final void Function(twitch.Emote) onPick;
  final void Function(twitch.Emote) onLongPress;

  const _EmoteSections({required this.sections, required this.match, required this.query, required this.onPick, required this.onLongPress});

  @override
  State<_EmoteSections> createState() => _EmoteSectionsState();
}

class _EmoteSectionsState extends State<_EmoteSections> with AutomaticKeepAliveClientMixin {
  final controller = ScrollController();
  late Set<String> collapsed = UserPrefs.instance.pickerCollapsed;

  @override
  bool get wantKeepAlive => true; // вкладка не пересоздаётся при переключении

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _page(int dir) {
    if (!controller.hasClients) return;
    final p = controller.position;
    final target = (p.pixels + dir * p.viewportDimension * 0.85).clamp(p.minScrollExtent, p.maxScrollExtent);
    controller.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// 2x вместо 4x: в сетке 48 px больше не нужно.
  static String _thumbUrl(twitch.Emote e) {
    final m = e.mipmap ?? const [];
    if (m.isEmpty) return '';
    return (m.length >= 2 ? m[1] : m.first) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final searching = widget.query.isNotEmpty;
    final slivers = <Widget>[];
    for (final section in widget.sections) {
      final items = section.emotes.where(widget.match).toList();
      if (items.isEmpty) continue;
      final isCollapsed = !searching && collapsed.contains(section.key);
      slivers.add(SliverToBoxAdapter(
        child: InkWell(
          onTap: () async {
            await UserPrefs.instance.togglePickerGroup(section.key);
            setState(() => collapsed = UserPrefs.instance.pickerCollapsed);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                Expanded(child: Text(section.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                Text('${items.length}', style: theme.textTheme.bodySmall),
                Icon(isCollapsed ? Icons.expand_more : Icons.expand_less, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ));
      if (!isCollapsed) {
        slivers.add(SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 48.0),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final e = items[i];
              final url = _thumbUrl(e);
              return InkWell(
                onTap: () => widget.onPick(e),
                onLongPress: () => widget.onLongPress(e),
                child: Padding(
                  padding: const EdgeInsets.all(6.0),
                  child: url.isEmpty
                      ? Center(child: Text(e.alt ?? e.name ?? '', style: const TextStyle(fontSize: 22)))
                      : Image(
                          image: ResizeImage(CachedNetworkImageProvider(url), height: 64, allowUpscaling: false, policy: ResizeImagePolicy.fit),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Center(child: Text(e.alt ?? '?', style: const TextStyle(fontSize: 18))),
                        ),
                ),
              );
            },
            childCount: items.length,
          ),
        ));
      }
    }
    if (slivers.isEmpty) {
      return Center(child: Text(tr('Nothing found', 'Ничего не найдено'), style: TextStyle(color: theme.hintColor)));
    }
    return Row(
      children: [
        Expanded(
          child: CustomScrollView(
            controller: controller,
            cacheExtent: 200, // небольшой запас — не грузим всё сразу
            slivers: slivers,
          ),
        ),
        // кнопки листания
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.keyboard_arrow_up), tooltip: tr('Page up', 'Вверх'), onPressed: () => _page(-1)),
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.keyboard_arrow_down), tooltip: tr('Page down', 'Вниз'), onPressed: () => _page(1)),
          ],
        ),
      ],
    );
  }
}
