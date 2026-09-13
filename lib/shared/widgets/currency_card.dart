import 'package:flutter/material.dart';
import '../../core/theme/tabby_colors.dart';
import '../../core/utils/currency_formatter.dart';

/// Financial balance card highlighting "You Owe" or "You're Owed"
/// with integer centavo formatting.
class CurrencyCard extends StatelessWidget {
  final String title;
  final int centavos;
  final String? subtitle;
  final bool isDebt;
  final IconData icon;
  final VoidCallback? onTap;

  const CurrencyCard({
    super.key,
    required this.title,
    required this.centavos,
    this.subtitle,
    required this.isDebt,
    required this.icon,
    this.onTap,
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
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TabbyColors.borderGray),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TabbyColors.secondaryMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 14,
                      color: themeColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyFormatter.formatCentavos(centavos),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDebt && centavos > 0
                        ? TabbyColors.debtRed
                        : (centavos > 0 ? TabbyColors.primaryCharcoal : TabbyColors.secondaryMuted),
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: TabbyColors.secondaryMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
