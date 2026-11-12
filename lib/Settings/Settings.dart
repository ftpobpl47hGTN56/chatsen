import 'package:bloc/bloc.dart';
import 'package:hive/hive.dart';

import 'SettingsEvent.dart';
import 'SettingsState.dart';

class Settings extends Bloc<SettingsEvent, SettingsState> {
  final Box settingsBox;

  Settings(this.settingsBox) : super(SettingsLoading()) {
    on<SettingsLoad>((event, emit) {
      // DearKing mod: чтение с проверкой типов — испорченное значение больше не вешает запуск
      bool b(String k, bool d) {
        final v = settingsBox.get(k);
        return v is bool ? v : d;
      }

      final mc = settingsBox.get('mentionCustom');
      emit(SettingsLoaded(
        setupScreen: b('setupScreen', true),
        notificationOnWhisper: b('notificationOnWhisper', false),
        notificationOnMention: b('notificationOnMention', false),
        notificationBackground: b('notificationBackground', false),
        messageTimestamp: b('messageTimestamp', false),
        messageImagePreview: b('messageImagePreview', true),
        messageLines: b('messageLines', false),
        messageAlternateBackground: b('messageAlternateBackground', false),
        mentionCustom: mc is List ? List<String>.from(mc.map((x) => '$x')) : <String>[],
        historyUseRecentMessages: b('historyUseRecentMessages', true),
        mentionWithAt: b('mentionWithAt', false),
      ));
    });
    on<SettingsChange>((event, emit) async {
      await settingsBox.put('setupScreen', event.state.setupScreen);
      await settingsBox.put('notificationOnWhisper', event.state.notificationOnWhisper);
      await settingsBox.put('notificationOnMention', event.state.notificationOnMention);
      await settingsBox.put('notificationBackground', event.state.notificationBackground);
      await settingsBox.put('messageTimestamp', event.state.messageTimestamp);
      await settingsBox.put('messageImagePreview', event.state.messageImagePreview);
      await settingsBox.put('messageLines', event.state.messageLines);
      await settingsBox.put('messageAlternateBackground', event.state.messageAlternateBackground);
      await settingsBox.put('mentionCustom', event.state.mentionCustom);
      await settingsBox.put('historyUseRecentMessages', event.state.historyUseRecentMessages);
      await settingsBox.put('mentionWithAt', event.state.mentionWithAt);
      emit(event.state);
    });
    add(SettingsLoad());
  }
}
