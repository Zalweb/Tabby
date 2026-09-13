import 'package:flutter/material.dart';
import '../../core/theme/tabby_colors.dart';
import '../../core/utils/currency_formatter.dart';

/// Financial balance card highlighting "You Owe" or "You're Owed"
/// with integer centavo formatting, re-architected to match Figma Node 7020:3430
/// geometry (16px corner radius, 8.5px squircle icon badge, pill status badge).
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
    final themeColor = isDebt ? TabbyColors.debtRed : TabbyColors.successGreen;
    final bgColor = isDebt ? TabbyColors.debtLight : TabbyColors.successLight;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TabbyColors.surfaceWhite,
            borderRadius: BorderRadius.circular(16), // Figma Rectangle 272/273 cornerRadius: 14.89px ≈ 16px
            border: Border.all(
              color: isDebt && centavos > 0
                  ? TabbyColors.debtRed.withValues(alpha: 0.20)
                  : (centavos > 0
                      ? TabbyColors.successGreen.withValues(alpha: 0.20)
                      : TabbyColors.borderGray),
              width: 1.2,
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x08000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
              if (centavos > 0)
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Squircle Icon Badge & Pill Status Chip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Icon Squircle Badge (Figma Rectangle 31: 25x25, cornerRadius 6.25px / 25% ratio)
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8.5),
                      border: Border.all(
                        color: themeColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: 16,
                        color: themeColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Pill Status Badge (Figma Rectangle 29/157 capsule geometry)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: centavos > 0 ? bgColor.withValues(alpha: 0.6) : TabbyColors.chipBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: centavos > 0 ? themeColor.withValues(alpha: 0.25) : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        badgeText ??
                            (isDebt
                                ? (centavos > 0 ? 'To Pay' : 'Settled')
                                : (centavos > 0 ? 'To Collect' : 'Settled')),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: centavos > 0 ? themeColor : TabbyColors.secondaryMuted,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Card Category Title
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: TabbyColors.secondaryMuted,
                  letterSpacing: 0.4,
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
                        ? TabbyColors.debtRed
                        : (centavos > 0 ? TabbyColors.primaryCharcoal : TabbyColors.secondaryMuted),
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
                        style: const TextStyle(
                          fontSize: 11,
                          color: TabbyColors.secondaryMuted,
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
      ),
    );
  }
}
