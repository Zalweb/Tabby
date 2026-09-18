import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../classroom/application/classroom_providers.dart';

/// FinWise Custom Floating Rounded Dock Navigation Bar
class MainScaffold extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({
    super.key,
    required this.navigationShell,
  });

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;
    final tasksDueToday = ref.watch(tasksDueTodayCountProvider);

    return Scaffold(
      backgroundColor: TabbyColors.bgCanvas,
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE8F8EE),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: _buildNavItem(
                  index: 0,
                  currentIndex: currentIndex,
                  label: 'Home',
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  onTap: () => _onTap(0),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 1,
                  currentIndex: currentIndex,
                  label: 'My Tabs',
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  onTap: () => _onTap(1),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 2,
                  currentIndex: currentIndex,
                  label: 'Tasks',
                  icon: Icons.task_outlined,
                  activeIcon: Icons.task_alt_rounded,
                  badgeCount: tasksDueToday,
                  onTap: () => _onTap(2),
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 3,
                  currentIndex: currentIndex,
                  label: 'Profile',
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  onTap: () => _onTap(3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required int currentIndex,
    required String label,
    required IconData icon,
    required IconData activeIcon,
    int badgeCount = 0,
    required VoidCallback onTap,
  }) {
    final isSelected = index == currentIndex;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active pill / circle highlight matching Figma FinWise dock
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    isSelected ? TabbyColors.brandEmerald : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color:
                              TabbyColors.brandEmerald.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    isSelected ? activeIcon : icon,
                    size: 24,
                    color: isSelected
                        ? TabbyColors.surfaceWhite
                        : TabbyColors.brandDarkTeal,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -5,
                      right: -8,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 16, minHeight: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: TabbyColors.alertRed,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? TabbyColors.brandEmerald
                                : const Color(0xFFE8F8EE),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            badgeCount > 9 ? '9+' : '$badgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? TabbyColors.brandDarkTeal
                    : TabbyColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
