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
                    // свой цвет: если выбран не из списка — показываем его, иначе радужный кружок
                    _PaletteSwatch(
                      custom: bg != null && !ThemeManager.backgrounds.any((c) => c?.toARGB32() == bg.toARGB32()) ? bg : null,
                      onTap: () async {
                        final picked = await ColorPickerDialog.show(context, initial: bg ?? const Color(0xFF18181B));
                        if (picked != null) await UserPrefs.instance.setBackground(picked);
                      },
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
                        // свой акцент из палитры перекрывает шаблоны
                        selected: UserPrefs.instance.accent == null && e.key == accent,
                        onTap: () {
                          UserPrefs.instance.setAccent(null);
                          BlocProvider.of<ThemeBloc>(context).add(ThemeColorSchemeChanged(colorScheme: e.key));
                        },
                      ),
                    // свой цвет акцента
                    _PaletteSwatch(
                      custom: UserPrefs.instance.accent,
                      onTap: () async {
                        final picked = await ColorPickerDialog.show(
                          context,
                          initial: UserPrefs.instance.accent ?? theme.colorScheme.primary,
                          title: tr('Accent color', 'Цвет акцента'),
                          sample: tr('Accent', 'Акцент'),
                          allowReset: UserPrefs.instance.accent != null,
                        );
                        if (picked == null) return;
                        await UserPrefs.instance.setAccent(picked == ColorPickerDialog.reset ? null : picked);
                      },
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


/// Кружок «Своя палитра»: радуга с иконкой или выбранный свой цвет с галочкой.
class _PaletteSwatch extends StatelessWidget {
  final Color? custom;
  final VoidCallback onTap;
  const _PaletteSwatch({required this.custom, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: custom,
          gradient: custom != null
              ? null
              : const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red]),
          border: Border.all(color: custom != null ? theme.colorScheme.primary : theme.dividerColor, width: custom != null ? 3 : 1),
        ),
        child: Icon(
          custom != null ? Icons.check : Icons.palette,
          size: 20,
          color: custom != null && custom!.computeLuminance() > 0.4 ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}

/// Простая палитра: оттенок, насыщенность, яркость + HEX. Без сторонних библиотек.
class ColorPickerDialog extends StatefulWidget {
  final Color initial;

  /// Заголовок окна; по умолчанию «Цвет фона».
  final String? title;

  /// Режим цвета ника: превью — текст этим цветом на текущем фоне. [sample] — какой текст показать.
  final String? sample;

  /// Показать кнопку «Сбросить» (вернёт [ColorPickerDialog.reset]).
  final bool allowReset;

  static const reset = Color(0x00000000);

  const ColorPickerDialog({Key? key, required this.initial, this.title, this.sample, this.allowReset = false}) : super(key: key);

  static Future<Color?> show(BuildContext context, {required Color initial, String? title, String? sample, bool allowReset = false}) =>
      showDialog<Color>(context: context, builder: (_) => ColorPickerDialog(initial: initial, title: title, sample: sample, allowReset: allowReset));

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController hex = TextEditingController(text: _hex(widget.initial));

  static String _hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _set(HSVColor v) => setState(() {
        hsv = v;
        hex.text = _hex(v.toColor());
      });

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  Widget _track(List<Color> colors) => Container(
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: LinearGradient(colors: colors)),
      );

  @override
  Widget build(BuildContext context) {
    final color = hsv.toColor();
    return AlertDialog(
      title: Text(widget.title ?? tr('Background color', 'Цвет фона')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // превью: фон + пример текста, как он будет выглядеть в чате
            Container(
              height: 64,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // режим ника: фон приложения, текст выбранным цветом; режим фона — наоборот
                color: widget.sample != null ? Theme.of(context).scaffoldBackgroundColor : color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: widget.sample != null
                  ? Text.rich(TextSpan(children: [
                      TextSpan(text: '${widget.sample}: ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                      TextSpan(text: tr('message text', 'текст сообщения')),
                    ]))
                  : Text(
                      tr('username: message text', 'ник: текст сообщения'),
                      style: TextStyle(color: color.computeLuminance() > 0.4 ? Colors.black : Colors.white),
                    ),
            ),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerLeft, child: Text(tr('Hue', 'Оттенок'))),
            _track([for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()]),
            Slider(value: hsv.hue, max: 360, onChanged: (v) => _set(hsv.withHue(v))),
            Align(alignment: Alignment.centerLeft, child: Text(tr('Saturation', 'Насыщенность'))),
            _track([hsv.withSaturation(0).toColor(), hsv.withSaturation(1).toColor()]),
            Slider(value: hsv.saturation, onChanged: (v) => _set(hsv.withSaturation(v))),
            Align(alignment: Alignment.centerLeft, child: Text(tr('Brightness', 'Яркость'))),
            _track([Colors.black, hsv.withValue(1).toColor()]),
            Slider(value: hsv.value, onChanged: (v) => _set(hsv.withValue(v))),
            TextField(
              controller: hex,
              maxLength: 6,
              decoration: const InputDecoration(prefixText: '#', labelText: 'HEX', counterText: ''),
              onSubmitted: (v) {
                final n = int.tryParse(v.trim().replaceAll('#', ''), radix: 16);
                if (n != null) _set(HSVColor.fromColor(Color(0xFF000000 | n)));
              },
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowReset) TextButton(onPressed: () => Navigator.of(context).pop(ColorPickerDialog.reset), child: Text(tr('Reset', 'Сбросить'))),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Cancel', 'Отмена'))),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(hex.text.trim(), radix: 16);
            Navigator.of(context).pop(n != null ? Color(0xFF000000 | n) : color);
          },
          child: Text(tr('Apply', 'Применить')),
        ),
      ],
    );
  }
}

/// Переключатели «Акцентные рамки» и «Полупрозрачные панели».
class PanelSwitches extends StatelessWidget {
  const PanelSwitches({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: UserPrefs.instance,
        builder: (context, _) {
          final p = UserPrefs.instance;
          return Column(
            children: [
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.border_style),
                title: Text(tr('Accent outlines', 'Акцентные рамки')),
                subtitle: Text(tr('2px accent border on buttons and windows', 'Рамка 2px цвета акцента у кнопок и окон')),
                value: p.accentBorders,
                onChanged: p.setAccentBorders,
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.opacity),
                title: Text(tr('Translucent panels', 'Полупрозрачные панели')),
                subtitle: Text(tr('Chat shows through the side menu and bars', 'Чат просвечивает сквозь шторку и панели')),
                value: p.translucent,
                onChanged: p.setTranslucent,
              ),
            ],
          );
        },
      );
}

/// Стиль @упоминаний: варианты с живым превью.
/// Размер шрифта чата: ползунок + живое превью (ник и текст сообщения, список зрителей).
class FontSizePicker extends StatelessWidget {
  const FontSizePicker({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: UserPrefs.instance,
        builder: (context, _) {
          final theme = Theme.of(context);
          final size = UserPrefs.instance.chatFontSize;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(tr('Chat font size', 'Размер шрифта чата'), style: theme.textTheme.titleMedium)),
                  Text('${size.round()} px', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                ]),
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.text_decrease),
                    tooltip: tr('Smaller', 'Меньше'),
                    onPressed: size > UserPrefs.minFont ? () => UserPrefs.instance.setChatFontSize(size - 1) : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: size,
                      min: UserPrefs.minFont,
                      max: UserPrefs.maxFont,
                      divisions: (UserPrefs.maxFont - UserPrefs.minFont).round(),
                      label: '${size.round()}',
                      onChanged: (v) => UserPrefs.instance.setChatFontSize(v.roundToDouble()),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.text_increase),
                    tooltip: tr('Bigger', 'Больше'),
                    onPressed: size < UserPrefs.maxFont ? () => UserPrefs.instance.setChatFontSize(size + 1) : null,
                  ),
                ]),
                // превью строки чата
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'DearKing: ', style: TextStyle(color: Color(0xFF8A2BE2), fontWeight: FontWeight.bold)),
                    TextSpan(text: tr('this is how chat looks', 'так будет выглядеть чат')),
                  ]),
                  style: TextStyle(fontSize: size),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Text(
                      tr('Also applies to the viewer list (a bit larger there)', 'Применяется и к списку зрителей (там чуть крупнее)'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ),
                  TextButton(
                    onPressed: size != 14 ? () => UserPrefs.instance.setChatFontSize(14) : null,
                    child: Text(tr('Reset', 'Сбросить')),
                  ),
                ]),
              ],
            ),
          );
        },
      );
}

class MentionStylePicker extends StatelessWidget {
  const MentionStylePicker({Key? key}) : super(key: key);

  static List<String> get names => [
        tr('Plain', 'Обычный'),
        tr('Accent', 'Акцент'),
        tr('Pill', 'Плашка'),
        tr('Outline', 'Рамка'),
        tr('Nick color', 'Цвет ника'),
      ];

  Widget _preview(BuildContext context, int style) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    const word = '@user123';
    switch (style) {
      case 0:
        return const Text(word, style: TextStyle(fontWeight: FontWeight.bold));
      case 2:
      case 3:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: style == 2 ? accent.withAlpha(50) : null,
            border: style == 2 ? null : Border.all(color: accent, width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(word, style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
        );
      case 4:
        return const Text(word, style: TextStyle(color: Color(0xFF1E90FF), fontWeight: FontWeight.bold));
      default:
        return Text(word, style: TextStyle(color: accent, fontWeight: FontWeight.bold));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: UserPrefs.instance,
        builder: (context, _) {
          final current = UserPrefs.instance.mentionStyle;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Mention style', 'Стиль упоминаний'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                // превью строки чата с выбранным стилем
                Row(children: [
                  Text(tr('nick: hi ', 'ник: привет ')),
                  _preview(context, current),
                  Text(tr(' how are you', ' как дела')),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < names.length; i++)
                      ChoiceChip(
                        label: Text(names[i]),
                        selected: current == i,
                        onSelected: (_) => UserPrefs.instance.setMentionStyle(i),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}

/// Значки у ника: все / только роли / скрыть.
class BadgeModePicker extends StatelessWidget {
  const BadgeModePicker({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: UserPrefs.instance,
        builder: (context, _) {
          final current = UserPrefs.instance.badgeMode;
          final options = [
            tr('All', 'Все'),
            tr('Roles only', 'Только роли'),
            tr('None', 'Скрыть'),
          ];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Badges next to nicknames', 'Значки у ника'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  tr('"Roles only" keeps streamer, mod, VIP and sub badges and hides event, game and 3rd-party badges.',
                      '«Только роли» оставляет значки стримера, модератора, VIP и сабки, а значки событий, игр и сторонних сервисов скрывает.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < options.length; i++)
                      ChoiceChip(
                        label: Text(options[i]),
                        selected: current == i,
                        onSelected: (_) => UserPrefs.instance.setBadgeMode(i),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}
