import '../../../shared/widgets/tabby_mascot_widget.dart';

import 'package:flutter/material.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../tabs/application/tabby_state.dart';
import '../domain/home_dashboard_summary.dart';

class HomeSurfaceCard extends StatelessWidget {
  const HomeSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: TabbyPalette.of(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: TabbyPalette.of(context).border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class HomeBalanceHero extends StatelessWidget {
  const HomeBalanceHero({
    super.key,
    required this.state,
    required this.summary,
  });
  final TabbyDashboardState state;
  final HomeDashboardSummary summary;
  @override
  Widget build(BuildContext context) {
    final p = TabbyPalette.of(context);
    final net = state.netBalanceCentavos;
    final outstanding =
        state.youOweCentavos > 0 || state.youAreOwedCentavos > 0;
    final title = net > 0
        ? 'You are owed'
        : net < 0
        ? 'You owe'
        : outstanding
        ? 'Balanced overall'
        : 'Nothing outstanding';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.soft,
            p.soft,
            Color.alphaBlend(
              TabbyColors.brandAmber.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.12
                    : 0.48,
              ),
              p.soft,
            ),
          ],
          stops: const [0, 0.48, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 12, 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(16) > 23;
            final words = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NET BALANCE',
                  style: TextStyle(
                    color: p.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  key: const ValueKey('home-net-direction'),
                  style: TextStyle(
                    color: p.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    CurrencyFormatter.formatCentavos(net.abs()),
                    key: const ValueKey('home-net-amount'),
                    style: TextStyle(
                      color: p.text,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  summary.totalTabs == 0
                      ? 'Your first tab starts here.'
                      : 'Across ${summary.activeTabs} active ${summary.activeTabs == 1 ? 'tab' : 'tabs'}',
                  style: TextStyle(
                    color: p.secondaryText,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            );
            final art = ExcludeSemantics(
              child: TabbyMascotWidget.art(
                pose: TabbyMascotPose.notebook,
                size: stacked ? 150 : constraints.maxWidth * 0.4,
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stacked) ...[
                  words,
                  const SizedBox(height: 12),
                  Center(child: art),
                ] else
                  Row(
                    children: [
                      Expanded(child: words),
                      const SizedBox(width: 8),
                      art,
                    ],
                  ),
                if (state.youOweCentavos > 0 &&
                    state.youAreOwedCentavos > 0) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Owed to you ${CurrencyFormatter.formatCentavos(state.youAreOwedCentavos)}  ·  You owe ${CurrencyFormatter.formatCentavos(state.youOweCentavos)}',
                    key: const ValueKey('home-both-obligations'),
                    style: TextStyle(color: p.text, fontSize: 12, height: 1.5),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class HomeTabsSummary extends StatelessWidget {
  const HomeTabsSummary({
    super.key,
    required this.summary,
    required this.onCreate,
    required this.onOpen,
  });
  final HomeDashboardSummary summary;
  final VoidCallback onCreate;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final p = TabbyPalette.of(context);
    return HomeSurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.layers_outlined, color: p.link, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your tabs',
                      style: TextStyle(
                        color: p.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${summary.totalTabs} ${summary.totalTabs == 1 ? 'tab' : 'tabs'}',
                    style: TextStyle(color: p.secondaryText, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Semantics(
                label:
                    '${summary.clearTabs} of ${summary.totalTabs} tabs have no outstanding balance for you',
                child: LinearProgressIndicator(
                  value: summary.clearance,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(20),
                  color: TabbyColors.brandAmber,
                  backgroundColor: p.soft,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${summary.clearTabs} of ${summary.totalTabs} clear for you',
                key: const ValueKey('home-clearance'),
                style: TextStyle(color: p.secondaryText, fontSize: 13),
              ),
              if (summary.totalTabs == 0)
                TextButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create your first tab'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePaymentSummary extends StatelessWidget {
  const HomePaymentSummary({super.key, required this.summary});
  final HomeDashboardSummary summary;
  @override
  Widget build(BuildContext context) {
    final p = TabbyPalette.of(context);
    Widget amount(String label, int cents, IconData icon, Color color) => Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: p.soft, shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: p.secondaryText, fontSize: 13),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyFormatter.formatCentavos(cents),
                  key: ValueKey('home-${label.toLowerCase()}'),
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return HomeSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Confirmed payments · recorded dates',
                  style: TextStyle(
                    color: p.secondaryText,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              Tooltip(
                message: 'Only confirmed payments are counted, using their recorded submission dates.',
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: p.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) =>
                c.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(16) > 23
                ? Column(
                    children: [
                      amount(
                        'Received',
                        summary.receivedCentavos,
                        Icons.south_west_rounded,
                        p.positiveText,
                      ),
                      const SizedBox(height: 16),
                      amount(
                        'Paid',
                        summary.paidCentavos,
                        Icons.south_east_rounded,
                        p.text,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: amount(
                          'Received',
                          summary.receivedCentavos,
                          Icons.south_west_rounded,
                          p.positiveText,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: p.border,
                      ),
                      Expanded(
                        child: amount(
                          'Paid',
                          summary.paidCentavos,
                          Icons.south_east_rounded,
                          p.text,
                        ),
                      ),
                    ],
                  ),
          ),
          if (summary.hasUnattributedPayments) ...[
            const SizedBox(height: 12),
            Text(
              'Some older payments have no recorded parties and are not included.',
              style: TextStyle(
                color: p.secondaryText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
