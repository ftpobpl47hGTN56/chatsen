import 'dart:io';

import '/BackgroundAudio/BackgroundAudioWrapper.dart';
import '/BackgroundDaemon/BackgroundDaemonCubit.dart';
import '/Pages/Settings.dart';
import '/Theme/ThemeManager.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../Consts.dart';
import '/Components/UI/WidgetBlur.dart';
import '/Pages/Account.dart';
import '/Pages/Search.dart';
import '/Components/UserPrefs.dart';
import '/StreamOverlay/StreamOverlayBloc.dart';
import '/StreamOverlay/StreamOverlayEvent.dart';
import '/StreamOverlay/StreamOverlayState.dart';
import '/Views/Userlist.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;

/// The [HomeDrawer] widget represents the drawer available on the home page. It features our [UserlistView] which displays all the users currently in a channel as well as giving us the way to access multiple options, accounts and features.
class HomeDrawer extends StatelessWidget {
  final twitch.Client? client;
  final twitch.Channel? channel;

  const HomeDrawer({
    Key? key,
    required this.client,
    required this.channel,
  }) : super(key: key);

  static void _backToChats(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
    } else if (scaffold != null && scaffold.isEndDrawerOpen) {
      scaffold.closeEndDrawer();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => WidgetBlur(
        child: Material(
          color: Theme.of(context).canvasColor.withAlpha(196),
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: channel != null
                          ? UserlistView(
                              channel: channel,
                            )
                          : ListView(),
                    ),
                    if (channel != null) _ModToolsRow(channel: channel!),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 12.0),
                      child: Card(
                        elevation: 8.0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (channel != null)
                              IconButton(
                                icon: Icon((Platform.isMacOS || Platform.isIOS) ? CupertinoIcons.play_fill : Icons.play_arrow),
                                onPressed: () async {
                                  if (!kPlayStoreRelease) {
                                    var bgDaemon = BlocProvider.of<BackgroundDaemonCubit>(context);
                                    var toggle = BlocProvider.of<StreamOverlayBloc>(context).state is StreamOverlayClosed;
                                    (BlocProvider.of<StreamOverlayBloc>(context).state is StreamOverlayClosed) ? BlocProvider.of<StreamOverlayBloc>(context).add(StreamOverlayOpen(channelName: channel!.name!.substring(1))) : BlocProvider.of<StreamOverlayBloc>(context).add(StreamOVerlayClose());
                                    await Future.delayed(Duration(seconds: 2));
                                    if (toggle) {
                                      await bgDaemon.pause();
                                    } else {
                                      await bgDaemon.play();
                                    }
                                  } else {
                                    (BlocProvider.of<StreamOverlayBloc>(context).state is StreamOverlayClosed) ? BlocProvider.of<StreamOverlayBloc>(context).add(StreamOverlayOpen(channelName: channel!.name!.substring(1))) : BlocProvider.of<StreamOverlayBloc>(context).add(StreamOVerlayClose());
                                  }
                                }, //launch('https://twitch.tv/${channel.name.substring(1)}'),
                                tooltip: tr('Open current channel\'s stream', 'Открыть трансляцию канала'),
                              ),
                            if (channel != null)
                              IconButton(
                                icon: Icon((Platform.isMacOS || Platform.isIOS) ? CupertinoIcons.search : Icons.search),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (BuildContext context) => SearchPage(
                                      channel: channel,
                                    ),
                                  ),
                                ),
                                tooltip: tr('Search in the current channel', 'Поиск по текущему каналу'),
                              ),
                            if (channel != null)
                              Container(
                                width: 1.0,
                                height: 24.0,
                                color: Theme.of(context).dividerColor,
                              ),
                            // DearKing mod: вместо пустой страницы ЛС (Twitch отключил whispers через IRC в 2023)
                            // — понятная кнопка возврата к чатам
                            IconButton(
                              icon: Icon(Icons.forum, color: Theme.of(context).colorScheme.primary),
                              onPressed: () => _backToChats(context),
                              tooltip: tr('Back to chats', 'Назад к чатам'),
                            ),
                            IconButton(
                              icon: Icon((Platform.isMacOS || Platform.isIOS) ? CupertinoIcons.person_crop_circle_fill_badge_plus : Icons.switch_account),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (BuildContext context) => AccountPage(
                                    client: client!,
                                  ),
                                ),
                              ),
                              tooltip: tr('Add or switch between your accounts', 'Добавить или сменить аккаунт'),
                            ),
                            // IconButton(
                            //   icon: Icon(Icons.account_circle),
                            //   onPressed: () => Navigator.of(context).push(
                            //     MaterialPageRoute(
                            //       builder: (BuildContext context) => ProfilePage(),
                            //     ),
                            //   ),
                            //   tooltip: 'Get your profile information',
                            // ),
                            IconButton(
                              icon: Icon((Platform.isMacOS || Platform.isIOS) ? CupertinoIcons.gear_alt_fill : Icons.settings),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (BuildContext context) => ThemeManager.routeWrapper(
                                    context: context,
                                    child: SettingsPage(
                                      client: client!,
                                    ),
                                  ),
                                ),
                              ),
                              tooltip: tr('Opens the settings page', 'Открыть настройки'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      width: 2.0,
                      height: 48.0,
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  Container(
                    width: 1.0,
                    color: Theme.of(context).dividerColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}


/// Панель инструментов мода в шторке: Chat cleaner, лимит рендера, размытие, «к чатам».
class _ModToolsRow extends StatefulWidget {
  final twitch.Channel channel;
  const _ModToolsRow({required this.channel});

  @override
  State<_ModToolsRow> createState() => _ModToolsRowState();
}

class _ModToolsRowState extends State<_ModToolsRow> {
  late final TextEditingController limitCtrl = TextEditingController(text: '${UserPrefs.instance.renderLimit}');

  @override
  void dispose() {
    limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyLimit(String v) async {
    final n = int.tryParse(v.trim());
    if (n == null) return;
    await UserPrefs.instance.setRenderLimit(n);
    limitCtrl.text = '${UserPrefs.instance.renderLimit}';
    // сразу подрезать уже накопленное во всех открытых чатах
    for (final ch in widget.channel.client?.channels ?? [widget.channel]) {
      twitch.ircTrim(ch.messages);
    }
    UserPrefs.instance.bump();
    if (mounted) setState(() {});
  }

  void _clean() {
    final count = widget.channel.messages.length;
    widget.channel.messages.clear();
    UserPrefs.instance.revealed.clear();
    UserPrefs.instance.bump();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('Messages cleared: $count', 'Очищено сообщений: $count'))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Card(
        elevation: 8.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Chat cleaner
              TextButton.icon(
                onPressed: _clean,
                icon: const Icon(Icons.cleaning_services, size: 20),
                label: Text(tr('Clear (${widget.channel.messages.length})', 'Очистить (${widget.channel.messages.length})')),
              ),
              const Spacer(),
              // лимит рендера
              Tooltip(
                message: tr('Max messages per chat (20–1000). Older ones are removed automatically. Fewer = smoother.', 'Максимум сообщений в чате (20–1000). Старые удаляются автоматически. Меньше — плавнее.'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.speed, size: 18, color: theme.colorScheme.onSurface.withAlpha(160)),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 52,
                      child: TextField(
                        controller: limitCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                        onSubmitted: _applyLimit,
                        onTapOutside: (_) {
                          _applyLimit(limitCtrl.text);
                          FocusManager.instance.primaryFocus?.unfocus();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // размытие вкл/выкл
              IconButton(
                tooltip: UserPrefs.instance.blur ? tr('Blur: on (heavy on GPU)', 'Размытие: вкл (тяжело для GPU)') : tr('Blur: off', 'Размытие: выкл'),
                icon: Icon(UserPrefs.instance.blur ? Icons.blur_on : Icons.blur_off, color: UserPrefs.instance.blur ? theme.colorScheme.primary : null),
                onPressed: () async {
                  await UserPrefs.instance.setBlur(!UserPrefs.instance.blur);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
