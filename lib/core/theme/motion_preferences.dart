import 'package:flutter/material.dart';

class TabbyMotion {
  TabbyMotion._();
  static bool disabled(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  static Duration duration(BuildContext context, Duration normal) =>
      disabled(context) ? Duration.zero : normal;
  static AnimationStyle? style(BuildContext context) =>
      disabled(context) ? AnimationStyle.noAnimation : null;
  static Future<DateTime?> datePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) => showDialog<DateTime>(
    context: context,
    animationStyle: style(context),
    builder: (_) => DatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
  static ThemeData theme(ThemeData base, bool reduced) => reduced
      ? base.copyWith(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _InstantTransition(),
              TargetPlatform.iOS: _InstantTransition(),
              TargetPlatform.macOS: _InstantTransition(),
              TargetPlatform.windows: _InstantTransition(),
              TargetPlatform.linux: _InstantTransition(),
              TargetPlatform.fuchsia: _InstantTransition(),
            },
          ),
        )
      : base;
}

class _InstantTransition extends PageTransitionsBuilder {
  const _InstantTransition();
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
