import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/session_scope.dart';
import '../../core/config/supabase_config.dart';
import '../../core/theme/tabby_palette.dart';

/// Feedback follows its owning route instead of painting on a covered page.
class TabbyFeedback {
  TabbyFeedback._(this._scope, this._messenger)
    : _session = SupabaseConfig.captureSession();
  final _TabbyFeedbackScopeState? _scope;
  final ScaffoldMessengerState? _messenger;
  final SessionStamp _session;
  static TabbyFeedback of(BuildContext context) => TabbyFeedback._(
    context.getInheritedWidgetOfExactType<_FeedbackOwner>()?.state,
    ScaffoldMessenger.maybeOf(context),
  );

  /// Realtime notices have no form context; prefer the top current sheet.
  static TabbyFeedback current(ScaffoldMessengerState fallback) {
    for (final scope in _TabbyFeedbackScopeState._mounted.reversed) {
      if (scope._isVisible &&
          ScaffoldMessenger.maybeOf(scope.context) == fallback) {
        return TabbyFeedback._(scope, fallback);
      }
    }
    return TabbyFeedback._(null, fallback);
  }

  void showSnackBar(SnackBar message) {
    if (!SupabaseConfig.isCurrentSession(_session)) return;
    final scope = _visibleScope;
    if (scope != null) {
      scope.show(message);
    } else if (_messenger?.mounted == true) {
      _messenger!.showSnackBar(message);
    }
  }

  void clearSnackBars() {
    if (!SupabaseConfig.isCurrentSession(_session)) return;
    final scope = _visibleScope;
    if (scope != null) {
      scope.clear();
    } else if (_messenger?.mounted == true) {
      _messenger!.clearSnackBars();
    }
  }

  // A save can pop its form before showing success. Re-resolve the visible
  // parent rather than painting into the closing sheet or dropping the result.
  _TabbyFeedbackScopeState? get _visibleScope {
    if (_scope?._isVisible == true) {
      return _scope;
    }
    return _messenger?.mounted == true ? current(_messenger!)._scope : null;
  }

  void hideCurrentSnackBar() => clearSnackBars();
}

class TabbyFeedbackScope extends StatefulWidget {
  const TabbyFeedbackScope({
    super.key,
    required this.child,
    this.expand = false,
  });
  final Widget child;
  final bool expand;
  @override
  State<TabbyFeedbackScope> createState() => _TabbyFeedbackScopeState();
}

class _FeedbackOwner extends InheritedWidget {
  const _FeedbackOwner({required this.state, required super.child});
  final _TabbyFeedbackScopeState state;
  @override
  bool updateShouldNotify(_FeedbackOwner oldWidget) => false;
}

class _TabbyFeedbackScopeState extends State<TabbyFeedbackScope> {
  static final _mounted = <_TabbyFeedbackScopeState>[];
  ModalRoute<dynamic>? _route;
  SnackBar? _message;
  Timer? _timer;
  // Stateful navigation keeps inactive branches mounted. Their local route may
  // still be current, but GoRouter disables its tickers while it is offstage.
  bool get _isVisible =>
      mounted &&
      _route?.isCurrent == true &&
      TickerMode.getValuesNotifier(context).value.enabled;
  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void show(SnackBar message) {
    _timer?.cancel();
    setState(() => _message = message);
    if (!MediaQuery.accessibleNavigationOf(context)) {
      _timer = Timer(message.duration, () {
        if (mounted) clear();
      });
    }
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    setState(() => _message = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mounted.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = TabbyPalette.of(context);
    final message = _message;
    return _FeedbackOwner(
      state: this,
      child: LayoutBuilder(
        builder: (context, bounds) => Column(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Material(
                  key: const ValueKey('active-sheet-feedback'),
                  color: p.soft,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: p.controlBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: bounds.hasBoundedHeight
                          ? bounds.maxHeight * 0.4
                          : 200,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                        child: Semantics(
                          liveRegion: true,
                          container: true,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DefaultTextStyle(
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: p.text,
                                    fontSize: 14,
                                    height: 1.45,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      message.content,
                                      if (message.action != null)
                                        TextButton(
                                          onPressed: () {
                                            final action = message.action!;
                                            clear();
                                            action.onPressed();
                                          },
                                          child: Text(message.action!.label),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Dismiss message',
                                onPressed: clear,
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: p.text,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.expand)
              Expanded(child: widget.child)
            else
              Flexible(child: widget.child),
          ],
        ),
      ),
    );
  }
}

/// Keeps Flutter's sheet route/back/draft behavior; adds only scoped feedback.
Future<T?> showTabbyBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) => showModalBottomSheet<T>(
  context: context,
  builder: (_) => TabbyFeedbackScope(child: Builder(builder: builder)),
  backgroundColor: backgroundColor,
  barrierLabel: barrierLabel,
  elevation: elevation,
  shape: shape,
  clipBehavior: clipBehavior,
  // Fill the route's current width, including after rotation or window resize.
  constraints: (constraints ?? const BoxConstraints()).copyWith(
    minWidth: double.infinity,
    maxWidth: double.infinity,
  ),
  barrierColor: barrierColor,
  isScrollControlled: isScrollControlled,
  scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
  useRootNavigator: useRootNavigator,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  showDragHandle: showDragHandle,
  useSafeArea: useSafeArea,
  routeSettings: routeSettings,
  transitionAnimationController: transitionAnimationController,
  anchorPoint: anchorPoint,
  sheetAnimationStyle: sheetAnimationStyle,
  requestFocus: requestFocus,
);

/// Full-screen presentation for a form that owns its back/draft behavior.
Future<T?> showTabbyFormPage<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(
    MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (_) => themes.wrap(
        _TabbyFormPage(
          child: Scaffold(
            key: const ValueKey('tabby-fullscreen-form'),
            backgroundColor: TabbyPalette.of(context).surface,
            // Existing forms apply their keyboard inset, including nested pickers.
            resizeToAvoidBottomInset: false,
            body: SafeArea(
              child: TabbyFeedbackScope(
                expand: true,
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TabbyFormPage extends InheritedWidget {
  const _TabbyFormPage({required super.child});
  @override
  bool updateShouldNotify(_TabbyFormPage oldWidget) => false;
}

bool isTabbyFormPage(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_TabbyFormPage>() != null;

/// Shares the same title and exit handler across compact and full-screen forms.
class TabbyFormHeader extends StatelessWidget {
  const TabbyFormHeader({super.key, required this.title, required this.onBack});
  final String title;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) {
    final full = isTabbyFormPage(context);
    final back = IconButton(
      tooltip: full ? 'Back' : 'Close',
      onPressed: onBack,
      icon: Icon(full ? Icons.arrow_back_rounded : Icons.close_rounded),
    );
    return Row(
      children: [
        if (full) back,
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        if (!full) back,
      ],
    );
  }
}

/// Keep Back reachable while long full-screen content scrolls under it.
class TabbyFormBody extends StatelessWidget {
  const TabbyFormBody({super.key, required this.header, required this.child});
  final Widget header;
  final Widget child;
  @override
  Widget build(BuildContext context) => isTabbyFormPage(context)
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: SingleChildScrollView(child: child)),
          ],
        )
      : SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, child],
          ),
        );
}
