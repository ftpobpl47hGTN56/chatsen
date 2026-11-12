import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '/Theme/ThemeBloc.dart';
import '/Theme/ThemeEvent.dart';
import '/Theme/ThemeManager.dart';
import '/Theme/ThemeState.dart';
import 'UserPrefs.dart';

/// Переключатель языка: две кнопки RU | EN.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isRu = UserPrefs.instance.isRu;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.translate, color: Theme.of(context).hintColor),
          const SizedBox(width: 16),
          Expanded(child: Text(tr('Language', 'Язык'), style: Theme.of(context).textTheme.titleMedium)),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'ru', label: Text('RU')),
              ButtonSegment(value: 'en', label: Text('EN')),
            ],
            selected: {isRu ? 'ru' : 'en'},
            onSelectionChanged: (v) async {
              await UserPrefs.instance.setLang(v.first);
              // строки берутся из tr() во время build — пересобираем всё дерево
              if (context.mounted) UserPrefs.rebuildAll(context);
            },
          ),
        ],
      ),
    );
  }
}

/// Оформление: два ряда кружков — «Фон» и «Акцент». Тап сразу применяет цвет.
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: UserPrefs.instance.appearance,
      builder: (context, _, __) => BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, state) {
          final accent = state is ThemeLoaded ? state.colorScheme : 'amber';
          final bg = UserPrefs.instance.background;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Background', 'Фон'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in ThemeManager.backgrounds)
                      _Swatch(
                        color: c ?? Colors.grey[900]!,
                        selected: c?.toARGB32() == bg?.toARGB32(),
                        // «стандарт» помечаем буквой A (auto)
                        label: c == null ? 'A' : null,
                        onTap: () => UserPrefs.instance.setBackground(c),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(tr('Accent', 'Акцент'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in ThemeManager.colors.entries)
                      _Swatch(
                        color: e.value.first as Color,
                        selected: e.key == accent,
                        onTap: () => BlocProvider.of<ThemeBloc>(context).add(ThemeColorSchemeChanged(colorScheme: e.key)),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final String? label;
  final VoidCallback onTap;

  const _Swatch({required this.color, required this.selected, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor = color.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          // обводка: у выбранного — акцентом, у остальных — тонкая, чтобы чёрный/белый было видно на любом фоне
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 20, color: onColor)
            : (label != null ? Center(child: Text(label!, style: TextStyle(color: onColor, fontWeight: FontWeight.bold))) : null),
      ),
    );
  }
}
