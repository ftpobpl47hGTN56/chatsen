import 'dart:ui';

import 'package:flutter/material.dart';
import '/Components/UserPrefs.dart';

class WidgetBlur extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final double blur;

  const WidgetBlur({
    required this.child,
    this.borderRadius,
    this.blur = 10.0,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        // переключатель размытия применяется сразу, без перезапуска
        animation: UserPrefs.instance,
        builder: (context, _) {
          // DearKing mod: без размытия — просто клип; BackdropFilter на весь экран сильно грузит GPU
          if (!UserPrefs.instance.blur) {
            return ClipRRect(
              borderRadius: borderRadius ?? BorderRadius.circular(0.0),
              child: Material(color: Colors.transparent, child: child),
            );
          }
          return _blurred();
        },
      );

  Widget _blurred() => Stack(
        children: <Widget>[
          ClipRRect(
            borderRadius: borderRadius ?? BorderRadius.circular(0.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blur,
                sigmaY: blur,
              ),
              child: Material(
                color: Colors.transparent,
                child: child,
              ),
            ),
          ),
        ],
      );
}
