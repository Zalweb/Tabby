import 'package:flutter/material.dart';

import '../../core/theme/tabby_palette.dart';
import '../../core/utils/currency_formatter.dart';

/// Financial balance card highlighting "You Owe" or "You're Owed"
/// designed with Tabby warm design system
/// squircle icon container, capsule status badge).
class CurrencyCard extends StatelessWidget {
  final String title;
  final int centavos;
  final String? subtitle;
  final bool isDebt;
  final IconData icon;
  final VoidCallback? onTap;
  final String? badgeText;

  const CurrencyCard({
    super.key,
    required this.title,
    required this.centavos,
    this.subtitle,
    required this.isDebt,
    required this.icon,
    this.onTap,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    // Warm obligation highlights keep debt distinct from confirmed success.
    final themeColor = TabbyPalette.of(context).link;
    final bgColor = isDebt
        ? TabbyPalette.of(context).accentTint
        : TabbyPalette.of(context).soft;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TabbyPalette.of(context).surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: TabbyPalette.of(context).border,
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Squircle Icon Badge & Capsule Status Chip
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Squircle Icon Badge
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Icon(icon, size: 20, color: themeColor)),
                ),
                const SizedBox(width: 6),
                // Capsule Status Badge
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      badgeText ??
                          (isDebt
                              ? (centavos > 0 ? 'To Pay' : 'Settled')
                              : (centavos > 0 ? 'To Collect' : 'Settled')),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: centavos > 0
                            ? (isDebt
                                  ? TabbyPalette.of(context).link
                                  : TabbyPalette.of(context).text)
                            : TabbyPalette.of(context).secondaryText,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Card Category Title
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyPalette.of(context).secondaryText,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            // Integer Centavo Currency Amount
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                CurrencyFormatter.formatCentavos(centavos),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDebt && centavos > 0
                      ? TabbyPalette.of(context).link
                      : TabbyPalette.of(context).text,
                  fontFamily: 'Inter',
                  letterSpacing: -0.5,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (centavos > 0) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: themeColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: TabbyPalette.of(context).secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
