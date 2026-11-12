import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import '/Commands/CommandsCubit.dart';
import '/Consts.dart';
import '/Settings/Settings.dart';
import '/Settings/SettingsState.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;
import '/Components/EmoteListModal.dart';
import 'Modal/UploadModal.dart';
import 'UI/NetworkImageWrapper.dart';
import 'WidgetTooltip.dart';
import 'package:collection/collection.dart';

/// [ChatInputBox] is our widget that features the input field used for every channel. It's feature rich and even contains autocompletion features!
class ChatInputBox extends StatefulWidget {
  final twitch.Client? client;
  final twitch.Channel? channel;

  const ChatInputBox({
    Key? key,
    required this.client,
    required this.channel,
  }) : super(key: key);

  @override
  ChatInputBoxState createState() => ChatInputBoxState();
}

class ChatInputBoxState extends State<ChatInputBox> {
  GlobalKey key = GlobalKey();
  TextEditingController textEditingController = TextEditingController();
  FocusNode focusNode = FocusNode();
  Timer? timer;

  // Реестр активных полей ввода по каналам — чтобы карточка юзера
  // (в т.ч. из бокового списка онлайн) могла вставить @ник в нужный инпут.
  static final Map<twitch.Channel, ChatInputBoxState> _instances = {};
  static ChatInputBoxState? of(twitch.Channel channel) => _instances[channel];

  @override
  void initState() {
    super.initState();
    if (widget.channel != null) _instances[widget.channel!] = this;
  }

  /// Диапазон «текущего слова» — от последнего пробела до курсора.
  /// Раньше везде использовалось text.split(' ').last, из-за чего
  /// автокомплит работал только в конце строки.
  TextRange _currentWordRange() {
    final text = textEditingController.text;
    var cursor = textEditingController.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    var start = cursor;
    while (start > 0 && !RegExp(r'\s').hasMatch(text[start - 1])) {
      start--;
    }
    return TextRange(start: start, end: cursor);
  }

  String get currentWord {
    final r = _currentWordRange();
    return textEditingController.text.substring(r.start, r.end);
  }

  /// Заменяет текущее слово на [replacement] + пробел и ставит курсор после него.
  void replaceCurrentWord(String replacement) {
    final text = textEditingController.text;
    final r = _currentWordRange();
    var after = text.substring(r.end);
    // если сразу за курсором был хвост слова (курсор внутри слова) — съедаем его
    final tail = RegExp(r'^\S*').firstMatch(after)!.group(0)!;
    after = after.substring(tail.length);
    final insert = after.startsWith(' ') ? replacement : '$replacement ';
    final newText = text.substring(0, r.start) + insert + after;
    final caret = r.start + insert.length + (after.startsWith(' ') ? 1 : 0);
    textEditingController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret.clamp(0, newText.length)),
    );
    focusNode.requestFocus();
    setState(() {});
  }

  /// Вставляет @ник в позицию курсора (используется карточкой юзера).
  void insertMention(String login) {
    final text = textEditingController.text;
    var cursor = textEditingController.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final pre = before.isEmpty || before.endsWith(' ') ? '' : ' ';
    final insert = '$pre@$login ';
    textEditingController.value = TextEditingValue(
      text: before + insert + after,
      selection: TextSelection.collapsed(offset: before.length + insert.length),
    );
    focusNode.requestFocus();
    setState(() {});
  }

  void appendText(String str) {
    setState(() {
      textEditingController.text = '${textEditingController.text}${textEditingController.text.isNotEmpty ? ' ' : ''}$str';
    });
  }

  @override
  void dispose() {
    if (widget.channel != null && _instances[widget.channel!] == this) _instances.remove(widget.channel!);
    textEditingController.dispose();
    focusNode.dispose();
    super.dispose();
    timer?.cancel();
    timer = null;
  }

  List<Widget> getAutoCompletionItems() => [
        if (currentWord.length >= 2 && !currentWord.startsWith('@'))
          for (var emote in widget.client!.emotes + widget.channel!.emotes + widget.channel!.transmitter!.emotes + widget.client!.emojis)
            if ('${emote.name}'.toLowerCase().contains(currentWord.toLowerCase()))
              WidgetTooltip(
                // message: '${emote.name}',
                message: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: NetworkImageW(
                          emote.mipmap!.last!,
                          height: 96.0,
                          fit: BoxFit.fitHeight,
                        ),
                      ),
                      Text(emote.name!),
                      Text(emote.provider!),
                    ],
                  ),
                ),

                child: InkWell(
                  onTap: () async => replaceCurrentWord('${emote.alt ?? emote.name}'),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      height: 32.0,
                      child: NetworkImageW(emote.mipmap!.last!),
                    ),
                  ),
                ),
              ),
      ];

  void send(String text, {bool remove = true}) {
    text = text.trim();

    // Command parser
    var firstCommand = BlocProvider.of<CommandsCubit>(context).state.firstWhereOrNull((command) => text.startsWith(command.trigger));
    if (firstCommand != null) {
      var textSplits = text.substring(firstCommand.trigger.length).split(' ');
      text = firstCommand.command;
      text = text.replaceAllMapped(
        RegExp(r'{\d*}'),
        (match) {
          var matchText = match.group(0) ?? '{}';
          var matchContent = matchText.substring(1, matchText.length - 1);
          var index = int.tryParse(matchContent);
          if (index != null && index < textSplits.length && index > 0) {
            return textSplits[index];
          }
          return '';
        },
      );
      text = text.replaceAllMapped(
        RegExp(r'{\d*\+}'),
        (match) {
          var matchText = match.group(0) ?? '{+}';
          var matchContent = matchText.substring(1, matchText.length - 2);
          var index = int.tryParse(matchContent);
          if (index != null && index < textSplits.length && index > 0) {
            return textSplits.skip(index).join(' ');
          }
          return '';
        },
      );
    }

    widget.channel?.send(text);
    if (remove) textEditingController.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var autocompletionItems = kUnverifiedVersion ? <Widget>[] : getAutoCompletionItems();
    var autocompletionItemsUsers = getAutoCompletionUsers();
    var autocompletionCommands = getAutoCompletionCommands();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 1.0,
          color: Theme.of(context).dividerColor,
        ),
        Padding(
          // MediaQuery.of(context).padding.
          padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left, right: MediaQuery.of(context).padding.right),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kDebugMode || widget.channel?.transmitter?.credentials?.token != null) ...[
                if (autocompletionCommands.isNotEmpty)
                  Container(
                    height: 40.0,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: autocompletionCommands,
                    ),
                  ),
                if (autocompletionItemsUsers.isNotEmpty)
                  Container(
                    height: 40.0,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: autocompletionItemsUsers,
                    ),
                  ),
                if (autocompletionItems.isNotEmpty)
                  Container(
                    height: 56.0,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: autocompletionItems,
                    ),
                  ),
                Container(
                  // height: 64.0,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          maxLines: textEditingController.text.isEmpty ? 1 : null,
                          maxLength: 498,
                          key: key,
                          focusNode: focusNode,
                          controller: textEditingController,
                          autofocus: false,
                          decoration: InputDecoration(
                            // contentPadding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                            filled: false,
                            isDense: true,
                            hintText: 'Message ${widget.channel!.name} as ${widget.channel!.transmitter!.credentials!.login}',
                            counterText: '',
                            // helperText: 'follow(420m)',
                            border: InputBorder.none,
                          ),
                          onChanged: (text) async => setState(() {}),
                          // перерисовать подсказки, когда курсор переставили тапом
                          onTap: () => Future.microtask(() => setState(() {})),
                          onSubmitted: send,
                        ),
                      ),
                      Container(
                        width: 40.0,
                        height: 40.0,
                        child: InkWell(
                          onTap: () async {
                            await UploadModal.show(
                              context,
                              channel: widget.channel!,
                            );
                          },
                          child: Icon(
                            (Platform.isMacOS || Platform.isIOS) ? CupertinoIcons.photo_fill : Icons.file_present,
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(64 * 3),
                          ),
                        ),
                      ),
                      Container(
                        width: 40.0,
                        height: 40.0,
                        child: InkWell(
                          onTap: () async {
                            await showModalBottomSheet(
                              isScrollControlled: true,
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (context) => SafeArea(
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                                  child: EmoteListModal(
                                    client: widget.client,
                                    channel: widget.channel,
                                    insertEmote: (emote) {
                                      // вставляем в позицию курсора, а не затираем последнее слово
                                      final text = textEditingController.text;
                                      var cursor = textEditingController.selection.baseOffset;
                                      if (cursor < 0 || cursor > text.length) cursor = text.length;
                                      final before = text.substring(0, cursor);
                                      final pre = before.isEmpty || before.endsWith(' ') ? '' : ' ';
                                      final insert = '$pre${emote!} ';
                                      textEditingController.value = TextEditingValue(
                                        text: before + insert + text.substring(cursor),
                                        selection: TextSelection.collapsed(offset: before.length + insert.length),
                                      );
                                      focusNode.requestFocus();
                                      Navigator.of(context).pop();
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ),
                              // backgroundColor: Colors.transparent,
                            );
                          },
                          child: Icon(
                            (Platform.isMacOS || Platform.isIOS) ? CupertinoIcons.smiley : Icons.emoji_emotions_outlined,
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(64 * 3),
                          ),
                        ),
                      ),
                      Container(
                        width: 40.0,
                        height: 40.0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapDown: (e) {
                            timer?.cancel();
                            timer = null;
                            timer = Timer.periodic(
                              Duration(seconds: 2),
                              (timer) {
                                send(textEditingController.text, remove: false);
                              },
                            );
                          },
                          onTapCancel: () {
                            timer?.cancel();
                            timer = null;
                          },
                          onTapUp: (e) {
                            timer?.cancel();
                            timer = null;
                          },
                          child: InkWell(
                            onTap: () => send(textEditingController.text),
                            child: Icon(
                              (Platform.isMacOS || Platform.isIOS) ? CupertinoIcons.arrow_right_circle : Icons.send,
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(64 * 3),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> getAutoCompletionUsers() {
    final word = currentWord;
    final startsWithAt = word.startsWith('@');
    // БАГ оригинала: условие `textEditingController.text.startsWith('@')`
    // проверяло начало ВСЕЙ строки, а не текущего слова — поэтому
    // «привет @ни...» не давало подсказок. Теперь смотрим только на слово у курсора.
    final query = (startsWithAt ? word.substring(1) : word).toLowerCase();
    if (startsWithAt ? query.isEmpty : query.length < 2) return [];

    final all = widget.channel!.users.values.expand((e) => e).toSet();
    final prefix = <String>[];
    final contains = <String>[];
    for (final user in all) {
      final u = user.toLowerCase();
      if (u.startsWith(query)) {
        prefix.add(user);
      } else if (u.contains(query)) {
        contains.add(user);
      }
    }
    prefix.sort((a, b) => a.length.compareTo(b.length));
    final matches = [...prefix, ...contains].take(40);

    return [
      for (var user in matches)
        InkWell(
          onTap: () async {
            var settings = BlocProvider.of<Settings>(context).state as SettingsLoaded;
            replaceCurrentWord(((settings.mentionWithAt || startsWithAt) ? '@' : '') + user);
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(startsWithAt ? '@$user' : user),
            ),
          ),
        ),
    ];
  }

  List<Widget> getAutoCompletionCommands() => [
        if (textEditingController.text.split(' ').last.isNotEmpty && !textEditingController.text.endsWith(' '))
          for (var cmd in BlocProvider.of<CommandsCubit>(context).state.where((command) => command.trigger.toLowerCase().startsWith(textEditingController.text.toLowerCase())))
            InkWell(
              onTap: () async {
                var splits = textEditingController.text.split(' ');
                splits.last = cmd.trigger;
                textEditingController.text = splits.join(' ') + ' ';
                textEditingController.selection = TextSelection.fromPosition(TextPosition(offset: textEditingController.text.length));
                focusNode.requestFocus();
                setState(() {});
              },
              child: WidgetTooltip(
                message: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(cmd.trigger, style: Theme.of(context).textTheme.headlineSmall),
                      Text(cmd.command),
                    ],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(cmd.trigger),
                  ),
                ),
              ),
            ),
      ];
}
