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
  static const _compactDuration = Duration(milliseconds: 260);
  static const _selectDuration = Duration(milliseconds: 240);
  static const _scrollThreshold = 20.0;
  static const _baseSlot = 52.0;
  static const _dockPadding = 6.0;
  static const _selectionInset = 4.0;
  static const _minimumSlot = 48.0;
  static const _dockHeight = 56.0;
  static const _iconSize = 24.0;
  static const _labelGap = 4.0;
  static const _maxLabelWidth = 104.0;
  static const Curve _dockCurve = Cubic(0.22, 1, 0.36, 1);
  static const _items = [
    ('Home', Icons.home_outlined, Icons.home_rounded),
    ('My Tabs', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
    ('Profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  late final AnimationController _compactController;
  late final List<AnimationController> _selectControllers;

  bool _compact = false;
  int _selectedIndex = 0;
  bool _reduceMotion = false;
  bool _userScrolling = false;
  double _downAccum = 0;
  double _upAccum = 0;

  @override
  void initState() {
    super.initState();
    _compactController = AnimationController(
      vsync: this,
      duration: _compactDuration,
      value: 1, // 1 = expanded, 0 = compact.
    );
    _selectControllers = List.generate(
      _items.length,
      (_) => AnimationController(vsync: this, duration: _selectDuration),
    );
    _selectedIndex = widget.navigationShell.currentIndex;
    _syncSelection(animate: false);
  }

  @override
  void dispose() {
    _compactController.dispose();
    for (final controller in _selectControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationShell.currentIndex != _selectedIndex) {
      // Branch changes restore the expanded dock and animate the new label.
      _selectedIndex = widget.navigationShell.currentIndex;
      _userScrolling = false;
      _downAccum = 0;
      _upAccum = 0;
      _syncSelection(animate: true);
      _setCompact(false);
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
      duration: controller.duration ?? _compactDuration,
      curve: _dockCurve,
    );
  }

  void _syncSelection({required bool animate}) {
    final selected = widget.navigationShell.currentIndex;
    for (var i = 0; i < _selectControllers.length; i++) {
      _apply(_selectControllers[i], i == selected ? 1 : 0, animate: animate);
    }
  }

  void _setCompact(bool value) {
    if (_compact == value) return;
    setState(() => _compact = value);
    _apply(_compactController, value ? 0 : 1, animate: true);
  }

  void _onNavTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  /// Listens only to user-driven, depth-zero vertical scrolling. Direction,
  /// depth and axis are checked before any state is mutated. Programmatic
  /// jumps, nested scrolls and overscroll are ignored. Direction changes, idle
  /// events and the top of the page reset the accumulator to prevent jitter.
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
      _userScrolling = notification.direction != ScrollDirection.idle;
      _downAccum = 0;
      _upAccum = 0;
      return false;
    }
    if (!_userScrolling || notification is! ScrollUpdateNotification) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.pixels < 0 || metrics.pixels > metrics.maxScrollExtent) {
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    if (delta.abs() < 0.01) return false;
    if (delta > 0) {
      _upAccum = 0;
      _downAccum += delta;
    } else {
      _downAccum = 0;
      _upAccum += -delta;
    }
    if (metrics.pixels <= 8) {
      if (_compact) _setCompact(false);
      return false;
    }
    if (_downAccum >= _scrollThreshold) {
      if (!_compact) _setCompact(true);
    } else if (_upAccum >= _scrollThreshold) {
      if (_compact) _setCompact(false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TabbyPalette.of(context);
    _reduceMotion = TabbyMotion.disabled(context);
    final path = GoRouterState.of(context).uri.path;
    final showAdd = path == '/home' || path == '/tabs';

    return Scaffold(
      backgroundColor: palette.canvas,
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: widget.navigationShell,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : 0.0;
                  return AnimatedBuilder(
                    animation: Listenable.merge([
                      _compactController,
                      ..._selectControllers,
                    ]),
                    builder: (context, _) => _buildDock(palette, available),
                  );
                },
              ),
            ),
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
    );
  }

  Widget _buildDock(TabbyPalette palette, double available) {
    final expanded = _compactController.value.clamp(0.0, 1.0).toDouble();
    final compactWidth = available
        .clamp(0.0, _baseSlot + 2 * _dockPadding)
        .toDouble();
    final width = compactWidth + (available - compactWidth) * expanded;
    final showCompactButton =
        _compact || width < _items.length * _minimumSlot + 2 * _dockPadding;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: SizedBox(
        width: width,
        height: _dockHeight,
        child: Material(
          key: const ValueKey('tabby-navigation-dock'),
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_dockHeight / 2),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _dockPadding),
            child: showCompactButton
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _compactNavItem(palette, _selectedIndex),
                  )
                : Row(
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
        ),
      ),
    );
  }

  Widget _navItem(TabbyPalette palette, int index, double width) {
    final item = _items[index];
    final selected = index == _selectedIndex;
    final selection = _selectControllers[index].value;
    final hidden = width < _minimumSlot;
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

    return ExcludeFocus(
      excluding: hidden,
      child: IgnorePointer(
        ignoring: hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: Semantics(
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
          ),
        ),
      ),
    );
  }

  Widget _compactNavItem(TabbyPalette palette, int index) {
    final item = _items[index];
    return Semantics(
      button: true,
      selected: true,
      label: item.$1,
      hint: 'Expand navigation',
      child: Tooltip(
        message: 'Show tabs',
        excludeFromSemantics: true,
        child: Material(
          color: palette.soft,
          shape: const CircleBorder(),
          child: InkWell(
            key: _tabKey(item.$1),
            customBorder: const CircleBorder(),
            onTap: () => _setCompact(false),
            child: SizedBox(
              width: _baseSlot,
              height: _baseSlot,
              child: Icon(item.$3, size: _iconSize, color: palette.link),
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
