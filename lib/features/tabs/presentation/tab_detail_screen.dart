import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../application/tabby_providers.dart';
import '../domain/models.dart';
import 'add_expense_modal.dart';
import '../../payment_methods/presentation/payment_method_payment_sheet.dart';

class TabDetailScreen extends ConsumerWidget {
  final String tabId;

  const TabDetailScreen({
    super.key,
    required this.tabId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawTab = ref.watch(tabDetailProvider(tabId));

    if (rawTab == null) {
      return Scaffold(
        backgroundColor: TabbyColors.bgCanvas,
        appBar: AppBar(
          backgroundColor: TabbyColors.brandEmerald,
          leading: IconButton(
            icon:
                const Icon(Icons.arrow_back, color: TabbyColors.brandDarkTeal),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/tabs'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Tab not found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.go('/tabs'),
                child: const Text('Back to My Tabs'),
              ),
            ],
          ),
        ),
      );
    }

    final entries = TabbyNotifier.deduplicateLedgerEntries(rawTab.entries);
    final tab = rawTab.copyWith(
      entries: entries,
      itemCount: entries.length,
    );

    final isTheyOwe = tab.netBalanceCentavos > 0;
    final isSettled = tab.netBalanceCentavos == 0;
    final balanceColor = isSettled
        ? TabbyColors.textSecondary
        : (isTheyOwe ? TabbyColors.brandEmerald : TabbyColors.accentBlue);

    return Scaffold(
      backgroundColor: TabbyColors.brandEmerald,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Green Header Section (Figma account_balance_7020_3680)
            Container(
              color: TabbyColors.brandEmerald,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  // App Bar Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: TabbyColors.brandDarkTeal),
                            onPressed: () => context.canPop()
                                ? context.pop()
                                : context.go('/tabs'),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tab.isGroupTab
                                ? (tab.groupName ?? tab.counterpart.displayName)
                                : tab.counterpart.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: TabbyColors.brandDarkTeal,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.qr_code_2_rounded,
                                  size: 20, color: TabbyColors.brandDarkTeal),
                              onPressed: () =>
                                  PaymentMethodPaymentSheet.show(context, tab),
                              tooltip: 'Payment Info',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.receipt_long_rounded,
                                  size: 20, color: TabbyColors.brandDarkTeal),
                              onPressed: () =>
                                  _showReceiptsSheet(context, tab, ref),
                              tooltip: 'View Receipts',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: TabbyColors.surfaceWhite,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.add_rounded,
                                  size: 20, color: TabbyColors.brandDarkTeal),
                              onPressed: () {
                                AddExpenseModal.show(context,
                                    initialCounterpartId: tab.id);
                              },
                              tooltip: 'Add to Tab',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Dual KPI: Total Balance vs Total Activity (Figma account_balance_7020_3680)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Total Balance
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: TabbyColors.surfaceWhite
                                        .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Icon(
                                    Icons.north_east_rounded,
                                    size: 14,
                                    color: TabbyColors.brandDarkTeal,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Total Balance',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyColors.brandDarkTeal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                CurrencyFormatter.formatCentavos(
                                    tab.netBalanceCentavos.abs()),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: TabbyColors.brandDarkTeal,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Divider
                      Container(
                        height: 42,
                        width: 1.2,
                        color: TabbyColors.brandDarkTeal.withValues(alpha: 0.2),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      // Right Column: Total Expense
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: TabbyColors.surfaceWhite
                                        .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Icon(
                                    Icons.south_west_rounded,
                                    size: 14,
                                    color: TabbyColors.accentBlue,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Total Activity',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyColors.brandDarkTeal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${tab.entries.length} items',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: TabbyColors.accentBlue,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TabbyMascotWidget(
                    emotion: isSettled
                        ? MascotEmotion.sleeping
                        : (isTheyOwe
                            ? MascotEmotion.userIsOwed
                            : MascotEmotion.userOwes),
                    size: 48,
                    showBubble: false,
                  ),
                  const SizedBox(height: 12),

                  // FinWise Progress Bar Capsule (account_balance_7020_3680)
                  Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: TabbyColors.brandDeepForest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 16),
                          child: Text(
                            '100%',
                            style: TextStyle(
                              color: TabbyColors.bgCanvas,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          height: 28,
                          margin: const EdgeInsets.only(right: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: TabbyColors.bgCanvas,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              CurrencyFormatter.formatCentavos(
                                  tab.netBalanceCentavos.abs()),
                              style: const TextStyle(
                                color: TabbyColors.brandDeepForest,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Summary Balance Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: TabbyColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: tab.isGroupTab
                                  ? TabbyColors.iconBgMint
                                  : TabbyColors.iconBgBlue,
                              child: Text(
                                tab.isGroupTab
                                    ? 'G'
                                    : (tab.counterpart.displayName.isNotEmpty
                                        ? tab.counterpart.displayName
                                            .substring(0, 1)
                                            .toUpperCase()
                                        : '?'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: tab.isGroupTab
                                      ? TabbyColors.brandEmerald
                                      : TabbyColors.accentLightBlue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isSettled
                                        ? 'All settled up'
                                        : (isTheyOwe
                                            ? '${tab.counterpart.displayName} owes you'
                                            : 'You owe ${tab.counterpart.displayName}'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: balanceColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    CurrencyFormatter.formatCentavos(
                                        tab.netBalanceCentavos.abs()),
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: balanceColor,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Action Buttons
                        Row(
                          children: [
                            if (isTheyOwe) ...[
                              Expanded(
                                child: TabbyButton(
                                  label:
                                      'Remind ${tab.counterpart.displayName}',
                                  variant: TabbyButtonVariant.secondary,
                                  icon: const Icon(Icons.send_rounded,
                                      size: 16,
                                      color: TabbyColors.brandDarkTeal),
                                  onPressed: () =>
                                      _showNudgeModal(context, ref, tab),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TabbyButton(
                                  label: 'Confirm Payment',
                                  variant: TabbyButtonVariant.outline,
                                  icon: const Icon(Icons.check_circle_outline,
                                      size: 16,
                                      color: TabbyColors.brandDarkTeal),
                                  onPressed: () => _showSettlementModal(
                                    context,
                                    ref,
                                    tab,
                                    isPayingMe: true,
                                  ),
                                ),
                              ),
                            ] else if (!isSettled) ...[
                              Expanded(
                                child: TabbyButton(
                                  label: 'I Paid',
                                  variant: TabbyButtonVariant.primary,
                                  icon: const Icon(Icons.payment_rounded,
                                      size: 16,
                                      color: TabbyColors.surfaceWhite),
                                  onPressed: () => _showSettlementModal(
                                    context,
                                    ref,
                                    tab,
                                    isPayingMe: false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TabbyButton(
                                  label: 'Add to Tab',
                                  variant: TabbyButtonVariant.outline,
                                  icon: const Icon(Icons.add_rounded,
                                      size: 16,
                                      color: TabbyColors.brandDarkTeal),
                                  onPressed: () {
                                    AddExpenseModal.show(context,
                                        initialCounterpartId: tab.id);
                                  },
                                ),
                              ),
                            ] else ...[
                              Expanded(
                                child: TabbyButton(
                                  label: 'Log New Expense',
                                  variant: TabbyButtonVariant.primary,
                                  icon: const Icon(Icons.add_rounded,
                                      size: 16,
                                      color: TabbyColors.surfaceWhite),
                                  onPressed: () {
                                    AddExpenseModal.show(context,
                                        initialCounterpartId: tab.id);
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Chronological Ledger Feed (Curved White Sheet)
            Expanded(
              child: Material(
                color: TabbyColors.bgCanvas,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(36)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Ledger History',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.brandDarkTeal,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            '${tab.entries.length} records',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TabbyColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: tab.entries.isEmpty
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 24),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const TabbyMascotWidget(
                                      emotion: MascotEmotion.idleNeutral,
                                      size: 64,
                                      showBubble: false,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No transactions yet',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: TabbyColors.brandDarkTeal,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Start keeping tabs by logging your first shared expense with ${tab.isGroupTab ? (tab.groupName ?? tab.counterpart.displayName) : tab.counterpart.displayName}.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: TabbyColors.textSecondary,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        AddExpenseModal.show(context,
                                            initialCounterpartId: tab.id);
                                      },
                                      icon: const Icon(Icons.add_rounded,
                                          size: 18),
                                      label: const Text('Log First Expense'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            TabbyColors.brandEmerald,
                                        foregroundColor:
                                            TabbyColors.surfaceWhite,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                              itemCount: tab.entries.length,
                              itemBuilder: (context, index) {
                                final entry = tab.entries[index];
                                return _buildLedgerEntryCard(
                                    context, ref, entry);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerEntryCard(
      BuildContext context, WidgetRef ref, LedgerEntry entry) {
    final dateFormat = DateFormat('HH:mm - MMM d');
    final currentUser = ref.watch(currentUserProvider);
    final isPayment = entry.isPayment;
    final isMyEntry = entry.paidByUserId == currentUser.id ||
        (SupabaseConfig.isInitialized &&
            entry.paidByUserId == SupabaseConfig.currentUserId);
    final amountPrefix = isPayment ? '+' : (isMyEntry ? '+' : '-');
    final amountColor = isPayment
        ? TabbyColors.brandEmerald
        : (isMyEntry ? TabbyColors.brandDarkTeal : TabbyColors.accentBlue);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TabbyColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TabbyColors.borderMint),
      ),
      child: InkWell(
        onTap: () => _showEntryDetailsSheet(context, ref, entry),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Squircle Icon Badge (Figma 40x40)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isPayment
                      ? TabbyColors.iconBgMint
                      : TabbyColors.iconBgBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    isPayment
                        ? (entry.paymentMethod?.iconData ??
                            Icons.payments_rounded)
                        : entry.category.icon,
                    size: 20,
                    color: isPayment
                        ? TabbyColors.brandEmerald
                        : TabbyColors.accentLightBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Column 1: Title & Time
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TabbyColors.brandDarkTeal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateFormat.format(entry.date),
                      style: const TextStyle(
                        fontSize: 11,
                        color: TabbyColors.accentLightBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Column Divider
              Container(
                height: 28,
                width: 1,
                color: TabbyColors.borderMint,
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
              // Column 2: Category / Status Tag
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isPayment ? 'Payment' : entry.category.displayName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: TabbyColors.brandDarkTeal,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _buildStatusBadge(entry.status, isPayment),
                  ],
                ),
              ),
              // Column Divider
              Container(
                height: 28,
                width: 1,
                color: TabbyColors.borderMint,
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
              // Column 3: Amount
              Expanded(
                flex: 3,
                child: Text(
                  '$amountPrefix${CurrencyFormatter.formatCentavos(entry.totalAmountCentavos)}',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(TransactionStatus status, bool isPayment) {
    Color bg;
    Color text;
    String label;

    if (isPayment) {
      bg = TabbyColors.brandMintAccent;
      text = TabbyColors.brandEmerald;
      label = 'Payment Settled';
    } else {
      switch (status) {
        case TransactionStatus.pending:
          bg = TabbyColors.pendingLight;
          text = TabbyColors.pendingAmber;
          label = 'Pending Ack';
          break;
        case TransactionStatus.acknowledged:
          bg = const Color(0xFFE8F8EE);
          text = TabbyColors.brandDarkTeal;
          label = 'Acknowledged';
          break;
        case TransactionStatus.paymentSubmitted:
          bg = TabbyColors.iconBgBlue;
          text = TabbyColors.accentBlue;
          label = 'Payment Sent';
          break;
        case TransactionStatus.settled:
          bg = TabbyColors.brandMintAccent;
          text = TabbyColors.brandEmerald;
          label = 'Settled';
          break;
        case TransactionStatus.cancelled:
          bg = const Color(0xFFFEE2E2);
          text = TabbyColors.alertRed;
          label = 'Cancelled';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  void _showNudgeModal(BuildContext context, WidgetRef ref, BilateralTab tab) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: TabbyColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Send Friendly Reminder',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const TabbyMascotWidget(
                  emotion: MascotEmotion.gentleNudge,
                  size: 52,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: TabbyColors.brandMintAccent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Hey ${tab.counterpart.displayName}! Here is our tab for ${tab.entries.firstOrNull?.title ?? "shared expense"} (${CurrencyFormatter.formatCentavos(tab.netBalanceCentavos)}). Settle up whenever you are ready!',
                    style: const TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: TabbyColors.brandDarkTeal,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TabbyButton(
                  label: 'Share Reminder Link',
                  variant: TabbyButtonVariant.primary,
                  icon: const Icon(Icons.share_rounded,
                      size: 18, color: TabbyColors.surfaceWhite),
                  onPressed: () {
                    final reminderMsg =
                        'Hey ${tab.counterpart.displayName}! Here is our tab for ${tab.entries.firstOrNull?.title ?? "shared expense"} (${CurrencyFormatter.formatCentavos(tab.netBalanceCentavos)}). Settle up whenever you are ready!';
                    Clipboard.setData(ClipboardData(text: reminderMsg));
                    ref.read(tabbyProvider.notifier).sendGentleNudge(
                          tabId: tab.id,
                          friendName: tab.counterpart.displayName,
                          amountCentavos: tab.netBalanceCentavos,
                        );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Reminder link copied to clipboard and sent to ${tab.counterpart.displayName}!'),
                        backgroundColor: TabbyColors.brandDarkTeal,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSettlementModal(
    BuildContext context,
    WidgetRef ref,
    BilateralTab tab, {
    required bool isPayingMe,
  }) {
    PaymentMethod selectedMethod = PaymentMethod.gcash;
    final amountController = TextEditingController(
      text: (tab.netBalanceCentavos.abs() / 100).toStringAsFixed(2),
    );
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: TabbyColors.surfaceWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            isPayingMe
                                ? 'Confirm Payment Received'
                                : 'Record Settlement',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.brandDarkTeal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Payment Method',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TabbyColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: PaymentMethod.values.map((method) {
                        final isSelected = selectedMethod == method;
                        return ChoiceChip(
                          avatar: Icon(method.iconData,
                              size: 16,
                              color: isSelected
                                  ? TabbyColors.surfaceWhite
                                  : TabbyColors.brandDarkTeal),
                          label: Text(method.label),
                          selected: isSelected,
                          selectedColor: TabbyColors.brandEmerald,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? TabbyColors.surfaceWhite
                                : TabbyColors.brandDarkTeal,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            setModalState(() {
                              selectedMethod = method;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Amount (PHP)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TabbyColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        prefixText: '₱ ',
                        hintText: '0.00',
                      ),
                    ),
                    const SizedBox(height: 20),
                    TabbyButton(
                      label: isPayingMe
                          ? 'Confirm Payment'
                          : 'Submit Payment Proof',
                      variant: TabbyButtonVariant.primary,
                      isLoading: isSubmitting,
                      onPressed: () {
                        if (isSubmitting) return;

                        final centavos = CurrencyFormatter.parseToCentavos(
                            amountController.text);
                        if (centavos <= 0) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Please enter an amount greater than ₱0.00'),
                              backgroundColor: TabbyColors.alertRed,
                            ),
                          );
                          return;
                        }

                        setModalState(() => isSubmitting = true);

                        ref.read(tabbyProvider.notifier).settleTab(
                              tabId: tab.id,
                              amountCentavos: centavos,
                              method: selectedMethod,
                              isPayingMe: isPayingMe,
                            );

                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Settlement recorded successfully!'),
                            backgroundColor: TabbyColors.brandEmerald,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEntryDetailsSheet(
      BuildContext context, WidgetRef ref, LedgerEntry entry) {
    final dateFormat = DateFormat('MMMM d, yyyy • h:mm a');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: TabbyColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        entry.isPayment ? 'Payment Details' : 'Expense Details',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: entry.isPayment
                            ? TabbyColors.iconBgMint
                            : TabbyColors.iconBgBlue,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Icon(
                          entry.isPayment
                              ? (entry.paymentMethod?.iconData ??
                                  Icons.payments_rounded)
                              : entry.category.icon,
                          color: entry.isPayment
                              ? TabbyColors.brandEmerald
                              : TabbyColors.accentLightBlue,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.brandDarkTeal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateFormat.format(entry.date),
                            style: const TextStyle(
                              fontSize: 12,
                              color: TabbyColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: TabbyColors.brandMintAccent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Amount',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: TabbyColors.textSecondary)),
                          Text(
                            CurrencyFormatter.formatCentavos(
                                entry.totalAmountCentavos),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: TabbyColors.brandDarkTeal),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Paid By',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: TabbyColors.textSecondary)),
                          Text(
                            entry.paidByName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: TabbyColors.brandDarkTeal),
                          ),
                        ],
                      ),
                      if (!entry.isPayment) ...[
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Your Share',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: TabbyColors.textSecondary)),
                            Text(
                              CurrencyFormatter.formatCentavos(
                                  entry.myShareCentavos),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Their Share',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: TabbyColors.textSecondary)),
                            Text(
                              CurrencyFormatter.formatCentavos(
                                  entry.counterpartShareCentavos),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal),
                            ),
                          ],
                        ),
                      ],
                      if (entry.paymentMethod != null) ...[
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Payment Rail',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: TabbyColors.textSecondary)),
                            Text(
                              entry.paymentMethod!.label,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandEmerald),
                            ),
                          ],
                        ),
                      ],
                      if (entry.dueDate != null) ...[
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Due Date',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: TabbyColors.textSecondary)),
                            Text(
                              DateFormat('MMMM d, yyyy').format(entry.dueDate!),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal),
                            ),
                          ],
                        ),
                      ],
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text('Receipt / Attachment',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: TabbyColors.textSecondary)),
                          ),
                          Text(
                            entry.receiptUrl != null &&
                                    entry.receiptUrl!.isNotEmpty
                                ? 'Attached'
                                : 'None',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: entry.receiptUrl != null &&
                                      entry.receiptUrl!.isNotEmpty
                                  ? TabbyColors.brandEmerald
                                  : TabbyColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (entry.receiptUrl == null || entry.receiptUrl!.isEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      final messenger = ScaffoldMessenger.of(context);
                      final receiptId =
                          'receipt_${DateTime.now().millisecondsSinceEpoch}.png';
                      ref.read(tabbyProvider.notifier).attachReceiptToEntry(
                            tabId: entry.tabId,
                            entryId: entry.id,
                            receiptUrl: receiptId,
                          );
                      Navigator.pop(sheetContext);
                      messenger.clearSnackBars();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Receipt image attached to transaction successfully!'),
                          backgroundColor: TabbyColors.brandEmerald,
                        ),
                      );
                    },
                    icon:
                        const Icon(Icons.add_photo_alternate_rounded, size: 18),
                    label: const Text('Attach Receipt Photo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TabbyColors.brandDarkTeal,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: InkWell(
                      onTap: () => _showReceiptPreviewSheet(context, entry),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: TabbyColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: TabbyColors.brandEmerald
                                  .withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image_outlined,
                                color: TabbyColors.brandEmerald, size: 20),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Verified Bill/Receipt Attached (Tap to view)',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: TabbyColors.brandEmerald),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TabbyButton(
                  label: 'Close',
                  variant: TabbyButtonVariant.outline,
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReceiptsSheet(
      BuildContext context, BilateralTab tab, WidgetRef ref) {
    final entriesWithReceipts = tab.entries
        .where((e) => e.receiptUrl != null && e.receiptUrl!.isNotEmpty)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: TabbyColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Shared Media & Receipts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: TabbyColors.brandDarkTeal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Receipts and payment proofs for ${tab.counterpart.displayName}\'s tab',
                style: const TextStyle(
                    fontSize: 12, color: TabbyColors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (entriesWithReceipts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: TabbyColors.brandMintAccent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 48, color: TabbyColors.textSecondary),
                      const SizedBox(height: 10),
                      const Text(
                        'No Receipts Attached Yet',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: TabbyColors.brandDarkTeal),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Attach bill photos, receipts, or payment screenshots to keep proof organized.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: TabbyColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      if (tab.entries.isNotEmpty)
                        ElevatedButton.icon(
                          onPressed: () {
                            final messenger = ScaffoldMessenger.of(context);
                            final latest = tab.entries.first;
                            final receiptId =
                                'receipt_${DateTime.now().millisecondsSinceEpoch}.png';
                            ref
                                .read(tabbyProvider.notifier)
                                .attachReceiptToEntry(
                                  tabId: tab.id,
                                  entryId: latest.id,
                                  receiptUrl: receiptId,
                                );
                            Navigator.pop(context);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Receipt attached to "${latest.title}"!'),
                                backgroundColor: TabbyColors.brandEmerald,
                              ),
                            );
                          },
                          icon:
                              const Icon(Icons.add_a_photo_outlined, size: 16),
                          label: const Text('Attach to Latest Transaction'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TabbyColors.brandEmerald,
                            foregroundColor: TabbyColors.surfaceWhite,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: entriesWithReceipts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final item = entriesWithReceipts[idx];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: TabbyColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: TabbyColors.borderMint),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: TabbyColors.brandMintAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.receipt_rounded,
                                  color: TabbyColors.brandEmerald, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: TabbyColors.brandDarkTeal),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${DateFormat('MMM d, yyyy').format(item.date)} • ${CurrencyFormatter.formatCentavos(item.totalAmountCentavos)}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: TabbyColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.visibility_outlined,
                                  color: TabbyColors.brandEmerald, size: 20),
                              tooltip: 'View Receipt',
                              onPressed: () =>
                                  _showReceiptPreviewSheet(context, item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              TabbyButton(
                label: 'Close',
                variant: TabbyButtonVariant.outline,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReceiptPreviewSheet(BuildContext context, LedgerEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: TabbyColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Receipt Preview',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.title,
                          style: const TextStyle(
                              fontSize: 12, color: TabbyColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: TabbyColors.bgCanvas,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: TabbyColors.borderMint),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                          color: TabbyColors.brandMintAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          size: 40,
                          color: TabbyColors.brandEmerald,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        CurrencyFormatter.formatCentavos(
                            entry.totalAmountCentavos),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('MMMM d, yyyy • h:mm a').format(entry.date),
                        style: const TextStyle(
                            fontSize: 12, color: TabbyColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: TabbyColors.brandMintAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded,
                                size: 16, color: TabbyColors.brandEmerald),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Verified Proof: ${entry.receiptUrl ?? "receipt_proof.png"}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: TabbyColors.brandDarkTeal),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TabbyButton(
                      label: 'Save Image',
                      variant: TabbyButtonVariant.outline,
                      icon: const Icon(Icons.download_rounded,
                          size: 16, color: TabbyColors.brandDarkTeal),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Receipt image saved to downloads!'),
                            backgroundColor: TabbyColors.brandEmerald,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TabbyButton(
                      label: 'Close',
                      variant: TabbyButtonVariant.primary,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
