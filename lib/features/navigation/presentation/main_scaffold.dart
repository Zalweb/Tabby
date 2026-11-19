import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';

import '../../../core/theme/motion_preferences.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../tabs/presentation/add_expense_modal.dart';

/// Bottom navigation shared by the Home, My Tabs and Profile branches.
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with TickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 260);
  static const _selectDuration = Duration(milliseconds: 240);
  static const _scrollThreshold = 12.0;
  static const _dockHeight = 56.0;
  static const _iconSize = 24.0;
  static const _labelGap = 4.0;
  static const _selectionInset = 4.0;
  static const _maxLabelWidth = 104.0;
  static const Curve _dockCurve = Cubic(0.22, 1, 0.36, 1);
  static const _items = [
    ('Home', Icons.home_outlined, Icons.home_rounded),
    ('My Tabs', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
    ('Profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  late final AnimationController _slideController;
  late final List<AnimationController> _selectControllers;

  bool _dockHidden = false;
  bool _branchHasPushedRoute = false;
  bool _reduceMotion = false;
  ScrollDirection _userScrollDirection = ScrollDirection.idle;
  double _downAccum = 0;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: _slideDuration,
      value: 0, // 0 = visible, 1 = below the viewport.
    );
    _selectControllers = List.generate(
      _items.length,
      (_) => AnimationController(vsync: this, duration: _selectDuration),
    );
    _selectedIndex = widget.navigationShell.currentIndex;
    _syncSelection(animate: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = TabbyMotion.disabled(context);
    if (reduced && !_reduceMotion) {
      _slideController.value = _dockHidden ? 1 : 0;
      _syncSelection(animate: false);
    }
    _reduceMotion = reduced;
  }

  @override
  void dispose() {
    _slideController.dispose();
    for (final controller in _selectControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationShell.currentIndex != _selectedIndex) {
      _selectedIndex = widget.navigationShell.currentIndex;
      _branchHasPushedRoute = _activeBranchCanPop;
      _userScrollDirection = ScrollDirection.idle;
      _downAccum = 0;
      _setDockHidden(false);
      _syncSelection(animate: true);
    }
  }

  void _apply(
    AnimationController controller,
    double target, {
    required bool animate,
  }) {
    if (!animate || _reduceMotion) {
      controller.value = target;
      return;
    }
    controller.animateTo(
      target,
      duration: controller.duration ?? _slideDuration,
      curve: _dockCurve,
    );
  }

  void _syncSelection({required bool animate}) {
    final selected = widget.navigationShell.currentIndex;
    for (var i = 0; i < _selectControllers.length; i++) {
      _apply(_selectControllers[i], i == selected ? 1 : 0, animate: animate);
    }
  }

  void _setDockHidden(bool value) {
    if (_dockHidden == value) return;
    setState(() => _dockHidden = value);
    _apply(_slideController, value ? 1 : 0, animate: true);
  }

  bool get _activeBranchCanPop {
    final branch = widget.navigationShell.route.branches[_selectedIndex];
    return branch.navigatorKey.currentState?.canPop() ?? false;
  }

  // Modal sheets in a branch Navigator must sit above its page controls.
  bool _onBranchNavigation(NavigationNotification notification) {
    final hasPushedRoute = _activeBranchCanPop;
    if (_branchHasPushedRoute != hasPushedRoute) {
      setState(() => _branchHasPushedRoute = hasPushedRoute);
    }
    return false;
  }

  void _onNavTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  /// Tracks depth-zero vertical user scrolls from the active route only.
  /// Programmatic changes, nested scrollables and overscroll do not affect the
  /// dock. Downward movement accumulates to 12 logical pixels; any real upward
  /// movement restores it immediately.
  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final origin = notification.context;
    if (origin != null &&
        (!TickerMode.valuesOf(origin).enabled ||
            ModalRoute.isCurrentOf(origin) == false)) {
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward &&
          _userScrollDirection != ScrollDirection.forward) {
        _downAccum = 0;
      }
      _userScrollDirection = notification.direction;
      return false;
    }
    if (notification is ScrollEndNotification) {
      _userScrollDirection = ScrollDirection.idle;
      return false;
    }
    if (notification is! ScrollUpdateNotification ||
        _userScrollDirection == ScrollDirection.idle) {
      return false;
    }

    final metrics = notification.metrics;
    if (metrics.pixels < metrics.minScrollExtent ||
        metrics.pixels > metrics.maxScrollExtent) {
      _downAccum = 0;
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    if (delta.abs() < 0.01) return false;

    if (delta > 0 && _userScrollDirection == ScrollDirection.reverse) {
      _downAccum += delta;
      if (_downAccum >= _scrollThreshold && !_dockHidden) {
        _setDockHidden(true);
      }
    } else if (delta < 0 && _userScrollDirection == ScrollDirection.forward) {
      _downAccum = 0;
      if (_dockHidden) _setDockHidden(false);
    } else {
      _downAccum = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TabbyPalette.of(context);
    final path = GoRouterState.of(context).uri.path;
    final showAdd = path == '/home' || path == '/tabs';
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final slideDistance = _dockHeight + (bottomInset > 12 ? bottomInset : 12);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: ClipRect(
        child: Stack(
          key: const ValueKey('tabby-navigation-body'),
          children: [
            Positioned.fill(
              child: NotificationListener<NavigationNotification>(
                onNotification: _onBranchNavigation,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScroll,
                  child: widget.navigationShell,
                ),
              ),
            ),
            if (!keyboardOpen && !_branchHasPushedRoute)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(child: _slidingDock(palette, slideDistance)),
                      if (showAdd) ...[
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          key: const ValueKey('navigation-create-tab'),
                          tooltip: 'Add tab',
                          shape: const CircleBorder(),
                          onPressed: () => AddExpenseModal.show(context),
                          child: const Icon(Icons.add_rounded, size: 30),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slidingDock(TabbyPalette palette, double slideDistance) =>
      ExcludeFocus(
        excluding: _dockHidden,
        child: ExcludeSemantics(
          excluding: _dockHidden,
          child: IgnorePointer(
            ignoring: _dockHidden,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _slideController,
                ..._selectControllers,
              ]),
              builder: (context, _) => Transform.translate(
                offset: Offset(0, slideDistance * _slideController.value),
                child: _buildDock(palette),
              ),
            ),
          ),
        ),
      );

  Widget _buildDock(TabbyPalette palette) => Material(
    key: const ValueKey('tabby-navigation-dock'),
    color: Colors.transparent,
    child: SizedBox(
      height: _dockHeight,
      child: Row(
        key: const ValueKey('tabby-navigation-bar'),
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _navItem(palette, i, constraints.maxWidth),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _navItem(TabbyPalette palette, int index, double width) {
    final item = _items[index];
    final selected = index == _selectedIndex;
    final selection = _selectControllers[index].value;
    final labelMaxWidth = (width - _iconSize - _labelGap - 2 * _selectionInset)
        .clamp(0.0, _maxLabelWidth)
        .toDouble();
    final label = SizeTransition(
      key: _labelKey(item.$1),
      axis: Axis.horizontal,
      alignment: AlignmentDirectional.centerStart,
      sizeFactor: _selectControllers[index],
      child: Padding(
        padding: const EdgeInsets.only(left: _labelGap),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: labelMaxWidth),
          child: ExcludeSemantics(
            child: Text(
              item.$1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: item.$1,
      child: Tooltip(
        message: item.$1,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: _tabKey(item.$1),
            borderRadius: BorderRadius.circular(24),
            onTap: () => _onNavTap(index),
            child: SizedBox(
              width: width,
              height: _dockHeight,
              child: Center(
                child: Ink(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      Colors.transparent,
                      palette.soft,
                      selection,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _selectionInset,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? item.$3 : item.$2,
                          size: _iconSize,
                          color: Color.lerp(
                            palette.secondaryText,
                            palette.link,
                            selection,
                          ),
                        ),
                        if (selected) label,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ValueKey<String> _tabKey(String label) =>
      ValueKey('navigation-tab-${label.toLowerCase().replaceAll(' ', '-')}');

  ValueKey<String> _labelKey(String label) =>
      ValueKey('navigation-label-${label.toLowerCase().replaceAll(' ', '-')}');
}
