import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';

/// FinWise Custom Floating Rounded Dock Navigation Bar
class MainScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final currentIndex = navigationShell.currentIndex;

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
              _buildNavItem(
                index: 0,
                currentIndex: currentIndex,
                label: 'Home',
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                onTap: () => _onTap(0),
              ),
              _buildNavItem(
                index: 1,
                currentIndex: currentIndex,
                label: 'My Tabs',
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long_rounded,
                onTap: () => _onTap(1),
              ),
              _buildNavItem(
                index: 2,
                currentIndex: currentIndex,
                label: 'Profile',
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                onTap: () => _onTap(2),
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
                color: isSelected ? TabbyColors.brandEmerald : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: TabbyColors.brandEmerald.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  isSelected ? activeIcon : icon,
                  size: 24,
                  color: isSelected ? TabbyColors.surfaceWhite : TabbyColors.brandDarkTeal,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? TabbyColors.brandDarkTeal : TabbyColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
