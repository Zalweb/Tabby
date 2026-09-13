import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../application/tabby_providers.dart';
import '../domain/models.dart';
import 'add_expense_modal.dart';

class TabDetailScreen extends ConsumerWidget {
  final String tabId;

  const TabDetailScreen({
    super.key,
    required this.tabId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabDetailProvider(tabId));
    final notifier = ref.read(tabbyProvider.notifier);

    if (tab == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Tab not found'),
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

    final isTheyOwe = tab.netBalanceCentavos > 0;
    final isSettled = tab.netBalanceCentavos == 0;
    final balanceColor = isSettled
        ? TabbyColors.secondaryMuted
        : (isTheyOwe ? TabbyColors.successGreen : TabbyColors.debtRed);

    return Scaffold(
      backgroundColor: TabbyColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          tab.isGroupTab
              ? (tab.groupName ?? tab.counterpart.displayName)
              : tab.counterpart.displayName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            onPressed: () => _showPaymentInfoSheet(context, tab),
            icon: const Icon(Icons.qr_code_2_rounded),
            tooltip: 'Payment Info / QR',
          ),
          IconButton(
            onPressed: () {
              AddExpenseModal.show(context, initialCounterpartId: tab.id);
            },
            icon: const Icon(Icons.add),
            tooltip: 'Add to Tab',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Summary Card
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TabbyColors.surfaceWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TabbyColors.borderGray),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: tab.isGroupTab
                            ? TabbyColors.pendingLight
                            : TabbyColors.backgroundLight,
                        child: Text(
                          tab.isGroupTab
                              ? '👥'
                              : tab.counterpart.displayName.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: tab.isGroupTab
                                ? TabbyColors.accentAmberDark
                                : TabbyColors.primaryCharcoal,
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
                                  ? 'All settled up! 🎉'
                                  : (isTheyOwe
                                      ? '${tab.counterpart.displayName} owes you'
                                      : 'You owe ${tab.counterpart.displayName}'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: balanceColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              CurrencyFormatter.formatCentavos(tab.netBalanceCentavos.abs()),
                              style: TextStyle(
                                fontSize: 28,
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
                            label: 'Remind 🐾',
                            variant: TabbyButtonVariant.secondary,
                            icon: const Text('🐾'),
                            onPressed: () => _showNudgeModal(context, ref, tab),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TabbyButton(
                            label: 'Confirm Bayad',
                            variant: TabbyButtonVariant.outline,
                            icon: const Icon(Icons.check_circle_outline, size: 16),
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
                            label: 'Bayad na ako / I Paid',
                            variant: TabbyButtonVariant.primary,
                            icon: const Icon(Icons.payment, size: 16, color: TabbyColors.surfaceWhite),
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
                            icon: const Icon(Icons.add, size: 16),
                            onPressed: () {
                              AddExpenseModal.show(context, initialCounterpartId: tab.id);
                            },
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: TabbyButton(
                            label: 'Log New Expense',
                            variant: TabbyButtonVariant.primary,
                            icon: const Icon(Icons.add, size: 16, color: TabbyColors.surfaceWhite),
                            onPressed: () {
                              AddExpenseModal.show(context, initialCounterpartId: tab.id);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Chronological Ledger Feed Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Ledger History',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: TabbyColors.primaryCharcoal,
                    ),
                  ),
                  Text(
                    '${tab.entries.length} records',
                    style: const TextStyle(
                      fontSize: 12,
                      color: TabbyColors.secondaryMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Chronological Feed
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: tab.entries.length,
                itemBuilder: (context, index) {
                  final entry = tab.entries[index];
                  return _buildLedgerEntryCard(context, entry);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerEntryCard(BuildContext context, LedgerEntry entry) {
    final dateFormat = DateFormat('MMM d, yyyy • h:mm a');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: entry.isPayment
                          ? TabbyColors.successLight
                          : TabbyColors.backgroundLight,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        entry.isPayment
                            ? (entry.paymentMethod?.icon ?? '💵')
                            : entry.category.emoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: TabbyColors.primaryCharcoal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Paid by ${entry.paidByName}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TabbyColors.secondaryMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.formatCentavos(entry.totalAmountCentavos),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: entry.isPayment
                              ? TabbyColors.successGreen
                              : TabbyColors.primaryCharcoal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _buildStatusBadge(entry.status, entry.isPayment),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateFormat.format(entry.date),
                    style: const TextStyle(
                      fontSize: 11,
                      color: TabbyColors.secondaryMuted,
                    ),
                  ),
                  if (entry.dueDate != null)
                    Text(
                      'Due: ${DateFormat('MMM d').format(entry.dueDate!)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: TabbyColors.debtRed,
                      ),
                    ),
                ],
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
      bg = TabbyColors.successLight;
      text = TabbyColors.successGreen;
      label = 'Payment Settled';
    } else {
      switch (status) {
        case TransactionStatus.pending:
          bg = TabbyColors.pendingLight;
          text = TabbyColors.accentAmberDark;
          label = 'Pending Ack';
          break;
        case TransactionStatus.acknowledged:
          bg = const Color(0xFFE5E7EB);
          text = TabbyColors.primaryCharcoal;
          label = 'Acknowledged';
          break;
        case TransactionStatus.paymentSubmitted:
          bg = TabbyColors.pendingLight;
          text = TabbyColors.accentAmberDark;
          label = 'Payment Sent';
          break;
        case TransactionStatus.settled:
          bg = TabbyColors.successLight;
          text = TabbyColors.successGreen;
          label = 'Settled';
          break;
        case TransactionStatus.cancelled:
          bg = TabbyColors.debtLight;
          text = TabbyColors.debtRed;
          label = 'Cancelled';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
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
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: TabbyColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Send Gentle Nudge 🐾',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: TabbyColors.primaryCharcoal,
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
                size: 54,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: TabbyColors.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: TabbyColors.borderGray),
                ),
                child: Text(
                  'Hey ${tab.counterpart.displayName}! Here\'s our tab for ${tab.entries.firstOrNull?.title ?? "shared expense"} (${CurrencyFormatter.formatCentavos(tab.netBalanceCentavos)}). Settle up whenever you\'re ready! 🐱🐾',
                  style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: TabbyColors.primaryCharcoal,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TabbyButton(
                label: 'Send via Messenger / Copy Link',
                variant: TabbyButtonVariant.primary,
                icon: const Icon(Icons.share_rounded, size: 18, color: TabbyColors.surfaceWhite),
                onPressed: () {
                  ref.read(tabbyProvider.notifier).sendGentleNudge(
                    tabId: tab.id,
                    friendName: tab.counterpart.displayName,
                    amountCentavos: tab.netBalanceCentavos,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('🐾 Gentle Nudge card copied! Sent to ${tab.counterpart.displayName}.'),
                      backgroundColor: TabbyColors.primaryCharcoal,
                    ),
                  );
                },
              ),
            ],
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isPayingMe ? 'Confirm Payment Received' : 'Record Settlement',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.primaryCharcoal,
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
                      fontWeight: FontWeight.w600,
                      color: TabbyColors.secondaryMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: PaymentMethod.values.map((method) {
                      final isSelected = selectedMethod == method;
                      return ChoiceChip(
                        label: Text('${method.icon} ${method.label}'),
                        selected: isSelected,
                        selectedColor: TabbyColors.accentAmber,
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
                    'Amount (₱)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: TabbyColors.secondaryMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      prefixText: '₱ ',
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 20),
                  TabbyButton(
                    label: isPayingMe ? 'Confirm Bayad na! 🎉' : 'Submit Payment Proof',
                    variant: TabbyButtonVariant.primary,
                    onPressed: () {
                      final centavos = CurrencyFormatter.parseToCentavos(amountController.text);
                      if (centavos <= 0) return;

                      ref.read(tabbyProvider.notifier).settleTab(
                        tabId: tab.id,
                        amountCentavos: centavos,
                        method: selectedMethod,
                        isPayingMe: isPayingMe,
                      );

                      Navigator.pop(context);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🎉 Settlement recorded! Tabby approves!'),
                          backgroundColor: TabbyColors.successGreen,
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPaymentInfoSheet(BuildContext context, BilateralTab tab) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: TabbyColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${tab.counterpart.displayName}\'s Payment Info',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TabbyColors.primaryCharcoal,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: TabbyColors.backgroundLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TabbyColors.borderGray),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner, size: 72, color: TabbyColors.primaryCharcoal),
                      SizedBox(height: 8),
                      Text(
                        'QR Ph Placeholder',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Text('💙', style: TextStyle(fontSize: 24)),
                title: const Text('GCash', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tab.counterpart.gcashNumber.isNotEmpty
                    ? tab.counterpart.gcashNumber
                    : '0917-XXX-XXXX'),
                trailing: const Icon(Icons.copy, size: 18),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('GCash number copied!')),
                  );
                },
              ),
              ListTile(
                leading: const Text('💚', style: TextStyle(fontSize: 24)),
                title: const Text('Maya', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tab.counterpart.mayaNumber.isNotEmpty
                    ? tab.counterpart.mayaNumber
                    : '0917-XXX-XXXX'),
                trailing: const Icon(Icons.copy, size: 18),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Maya number copied!')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
