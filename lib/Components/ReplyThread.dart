import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;

import 'ChatInputBox.dart';
import 'ChatMessage.dart';
import 'UserPrefs.dart';

/// Ветка ответов (как «Discussion» на десктопе): исходное сообщение + все ответы.
/// Открывается тапом по шапке «↪ @ник: …», по «Ответов: N» или из меню сообщения.
class ReplyThread extends StatefulWidget {
  final twitch.Message message;
  final ChatInputBoxState? input;

  const ReplyThread({Key? key, required this.message, this.input}) : super(key: key);

  static Future<void> show(BuildContext context, {required twitch.Message message, ChatInputBoxState? input}) {
    final inp = input ?? (message.channel != null ? ChatInputBoxState.of(message.channel!) : null);
    return showChatsenSheet(context, (_) => ReplyThread(message: message, input: inp));
  }

  @override
  State<ReplyThread> createState() => _ReplyThreadState();
}

class _ReplyThreadState extends State<ReplyThread> {
  Timer? _timer;

  /// Корень ветки: для ответа — его thread-родитель, для обычного сообщения — оно само.
  String? get rootId => widget.message.threadId ?? widget.message.id;

  @override
  void initState() {
    super.initState();
    // новые ответы приходят в общий список канала — просто перерисовываемся раз в секунду
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = widget.message.channel?.messages ?? const <twitch.Message>[];
    final root = all.firstWhereOrNull((m) => m.id == rootId);
    final replies = all.where((m) => m.threadId == rootId && m.id != rootId).toList();
    // корень мог уже удалиться автоочисткой — тогда покажем его текст из тегов первого ответа
    final rootFallback = root == null ? replies.firstWhereOrNull((m) => m.replyParentId == rootId) ?? widget.message : null;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.forum_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(tr('Thread', 'Ветка'), style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(tr('${replies.length} replies', 'Ответов: ${replies.length}'), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          // исходное сообщение
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
            ),
            child: root != null
                ? ChatMessage(message: root, inThread: true)
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '@${rootFallback?.replyParentName ?? ''}: ', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                        TextSpan(text: rootFallback?.replyParentBody ?? tr('(original message is no longer in chat)', '(исходное сообщение уже удалено из чата)')),
                      ]),
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: replies.isEmpty
                ? Center(child: Text(tr('No replies yet', 'Ответов пока нет'), style: TextStyle(color: theme.hintColor)))
                : ListView.builder(
                    padding: const EdgeInsets.only(left: 16),
                    itemCount: replies.length,
                    itemBuilder: (context, i) => ChatMessage(key: ObjectKey(replies[i]), message: replies[i], inThread: true),
                  ),
          ),
          if (widget.input != null && widget.input!.canSend)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: FilledButton.icon(
                icon: const Icon(Icons.reply),
                label: Text(tr('Reply in thread', 'Ответить в ветке')),
                onPressed: () {
                  // отвечаем последнему сообщению ветки (или корню, если ответов нет)
                  final target = replies.isNotEmpty ? replies.last : (root ?? widget.message);
                  Navigator.of(context).pop();
                  widget.input!.startReply(target);
                },
              ),
            ),
        ],
      ),
    );
  }
}
