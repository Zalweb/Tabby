import '../../../shared/widgets/tabby_feedback.dart';
import 'recurrence_screen.dart';
import '../domain/custom_split.dart';
import 'custom_split_form.dart';
import 'contact_claim_screen.dart';
import 'expense_review_screen.dart';
import '../domain/m2_capabilities.dart';
import '../application/expense_changes.dart';
import 'expense_change_screen.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../../../core/theme/motion_preferences.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/receipt_attachment_service.dart';
import '../../../core/services/receipt_blob_store.dart';
import '../../../core/services/form_draft_store.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/receipt_source_sheet.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../application/tabby_providers.dart';
import '../domain/models.dart';
import '../domain/pair_obligations.dart';
import 'add_expense_modal.dart';
import 'payment_decision_actions.dart';
import 'payment_draft_form.dart';
import '../../payment_methods/presentation/payment_method_payment_sheet.dart';

class TabDetailScreen extends ConsumerStatefulWidget {
  final String tabId;

  const TabDetailScreen({super.key, required this.tabId});

  @override
  ConsumerState<TabDetailScreen> createState() => _TabDetailScreenState();
}

class _TabDetailScreenState extends ConsumerState<TabDetailScreen> {
  String get tabId => widget.tabId;
  int _historyLimit = 50;
  String? _historyScope;

  @override
  Widget build(BuildContext context) {
    final session = SupabaseConfig.captureSession();
    final scope = '$tabId:${session.accountId}:${session.generation}';
    if (_historyScope != scope) {
      _historyScope = scope;
      _historyLimit = 50;
    }
    final rawTab = ref.watch(tabDetailProvider(tabId));

    if (rawTab == null) {
      return Scaffold(
        backgroundColor: TabbyPalette.of(context).canvas,
        appBar: AppBar(
          backgroundColor: TabbyPalette.of(context).canvas,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: TabbyPalette.of(context).text),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/tabs'),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Tab not found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: TabbyPalette.of(context).text,
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
    final tab = rawTab.copyWith(entries: entries, itemCount: entries.length);

    final isTheyOwe = tab.netBalanceCentavos > 0;
    final isSettled = tab.netBalanceCentavos == 0;
    final balanceColor = isSettled
        ? TabbyPalette.of(context).secondaryText
        : (isTheyOwe
              ? TabbyPalette.of(context).positiveText
              : TabbyPalette.of(context).link);

    return Scaffold(
      backgroundColor: TabbyPalette.of(context).canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, viewport) => Column(
            children: [
              // Shared warm header, with scroll room for large text.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: viewport.maxHeight * 0.7,
                ),
                child: SingleChildScrollView(
                  child: Container(
                    color: TabbyPalette.of(context).canvas,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      children: [
                        // App Bar Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.arrow_back,
                                      color: TabbyPalette.of(context).text,
                                    ),
                                    onPressed: () => context.canPop()
                                        ? context.pop()
                                        : context.go('/tabs'),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      tab.isGroupTab
                                          ? (tab.groupName ??
                                                tab.counterpart.displayName)
                                          : tab.counterpart.displayName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                        color: TabbyPalette.of(context).text,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: TabbyPalette.of(context).surface,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.qr_code_2_rounded,
                                      size: 20,
                                      color: TabbyPalette.of(context).text,
                                    ),
                                    onPressed: () => tab.isGroupTab
                                        ? _showGroupObligations(
                                            context,
                                            ref,
                                            tab,
                                          )
                                        : PaymentMethodPaymentSheet.show(
                                            context,
                                            tab,
                                          ),
                                    tooltip: 'Payment Info',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: TabbyPalette.of(context).surface,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.receipt_long_rounded,
                                      size: 20,
                                      color: TabbyPalette.of(context).text,
                                    ),
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
                                    color: TabbyPalette.of(context).surface,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.add_rounded,
                                      size: 20,
                                      color: TabbyPalette.of(context).text,
                                    ),
                                    onPressed: () {
                                      AddExpenseModal.show(
                                        context,
                                        initialCounterpartId: tab.id,
                                      );
                                    },
                                    tooltip: 'Add to Tab',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Summary Balance Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: TabbyPalette.of(context).surface,
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
                                        ? TabbyPalette.of(context).soft
                                        : TabbyPalette.of(context).accentTint,
                                    child: Text(
                                      tab.isGroupTab
                                          ? 'G'
                                          : (tab
                                                    .counterpart
                                                    .displayName
                                                    .isNotEmpty
                                                ? tab.counterpart.displayName
                                                      .substring(0, 1)
                                                      .toUpperCase()
                                                : '?'),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: tab.isGroupTab
                                            ? TabbyPalette.of(context).link
                                            : TabbyPalette.of(context).link,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tab.isGroupTab
                                              ? 'Your net position in this group'
                                              : isSettled
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
                                            tab.netBalanceCentavos.abs(),
                                          ),
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
                              if (tab.isGroupTab)
                                _groupObligations(context, ref, tab)
                              else
                                Row(
                                  children: [
                                    if (isTheyOwe) ...[
                                      Expanded(
                                        child: TabbyButton(
                                          label:
                                              'Remind ${tab.counterpart.displayName}',
                                          variant: TabbyButtonVariant.secondary,
                                          icon: Icon(
                                            Icons.send_rounded,
                                            size: 16,
                                            color: TabbyPalette.of(context)
                                                .text,
                                          ),
                                          onPressed: () => _showNudgeModal(
                                            context,
                                            ref,
                                            tab,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TabbyButton(
                                          label: 'Record received cash',
                                          variant: TabbyButtonVariant.outline,
                                          icon: Icon(
                                            Icons.check_circle_outline,
                                            size: 16,
                                            color: TabbyPalette.of(context)
                                                .text,
                                          ),
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
                                          icon: const Icon(
                                            Icons.payment_rounded,
                                            size: 16,
                                            color: TabbyColors.surfaceWhite,
                                          ),
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
                                          icon: Icon(
                                            Icons.add_rounded,
                                            size: 16,
                                            color: TabbyPalette.of(context)
                                                .text,
                                          ),
                                          onPressed: () {
                                            AddExpenseModal.show(
                                              context,
                                              initialCounterpartId: tab.id,
                                            );
                                          },
                                        ),
                                      ),
                                    ] else ...[
                                      Expanded(
                                        child: TabbyButton(
                                          label: 'Log New Expense',
                                          variant: TabbyButtonVariant.primary,
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 16,
                                            color: TabbyColors.surfaceWhite,
                                          ),
                                          onPressed: () {
                                            AddExpenseModal.show(
                                              context,
                                              initialCounterpartId: tab.id,
                                            );
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
                ),
              ),

              // Chronological Ledger Feed (Curved White Sheet)
              Expanded(
                child: Material(
                  color: TabbyPalette.of(context).canvas,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(36),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Text(
                              'Ledger History',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: TabbyPalette.of(context).text,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (M2Capabilities.contactClaiming &&
                                tab.isTabOnlyParticipant)
                              IconButton(
                                tooltip: 'Invite contact claim',
                                icon: const Icon(Icons.person_add_alt),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ContactClaimInvite(
                                        contactId: tab.counterpart.id,
                                        tabId: tab.id,
                                        queue: ref
                                            .read(tabbyProvider.notifier)
                                            .m2Commands,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            if (M2Capabilities.recurring &&
                                tab.entries.any(
                                  (e) =>
                                      !e.isPayment && e.participants.isNotEmpty,
                                ))
                              IconButton(
                                tooltip: 'Repeat expense',
                                icon: const Icon(Icons.event_repeat),
                                onPressed: () {
                                  final entry = tab.entries.firstWhere(
                                    (e) =>
                                        !e.isPayment &&
                                        e.participants.isNotEmpty,
                                  );
                                  final shares = {
                                    for (final p in entry.participants)
                                      PartyRef(
                                        kind:
                                            tab.isTabOnlyParticipant &&
                                                p.userId == tab.counterpart.id
                                            ? PartyKind.contact
                                            : PartyKind.user,
                                        id: p.userId,
                                      ): p.shareAmountCentavos,
                                  };
                                  final split = CustomSplit(baseShares: shares);
                                  final payer = shares.keys.singleWhere(
                                    (p) => p.id == entry.paidByUserId,
                                  );
                                  final queue = ref
                                      .read(tabbyProvider.notifier)
                                      .m2Commands;
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => RecurrenceManager(
                                        tabId: tab.id,
                                        queue: queue,
                                        templateTransactionId: entry.id,
                                        template: split.toCommand(
                                          actor: queue.actor,
                                          tabId: tab.id,
                                          payer: payer,
                                          description: entry.title,
                                          category: entry.category.name,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            if (M2Capabilities.customSplits)
                              IconButton(
                                tooltip: 'Custom split',
                                icon: const Icon(Icons.calculate_outlined),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => CustomSplitForm(
                                      tabId: tab.id,
                                      queue: ref
                                          .read(tabbyProvider.notifier)
                                          .m2Commands,
                                      parties: tab.isGroupTab
                                          ? {
                                              for (final member in tab.members)
                                                PartyRef(
                                                  kind: PartyKind.user,
                                                  id: member.id,
                                                ): member.displayName,
                                            }
                                          : {
                                              PartyRef(
                                                kind: PartyKind.user,
                                                id: ref
                                                    .read(currentUserProvider)
                                                    .id,
                                              ): 'You',
                                              PartyRef(
                                                kind: tab.isTabOnlyParticipant
                                                    ? PartyKind.contact
                                                    : PartyKind.user,
                                                id: tab.counterpart.id,
                                              ): tab.counterpart.displayName,
                                            },
                                    ),
                                  ),
                                ),
                              ),
                            Text(
                              '${tab.entries.length} records',
                              style: TextStyle(
                                fontSize: 12,
                                color: TabbyPalette.of(context).secondaryText,
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
                                  horizontal: 24,
                                  vertical: 24,
                                ),
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
                                      Text(
                                        'No transactions yet',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: TabbyPalette.of(context).text,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Start keeping tabs by logging your first shared expense with ${tab.isGroupTab ? (tab.groupName ?? tab.counterpart.displayName) : tab.counterpart.displayName}.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: TabbyPalette.of(context)
                                              .secondaryText,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          AddExpenseModal.show(
                                            context,
                                            initialCounterpartId: tab.id,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.add_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Log First Expense'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              TabbyColors.brandAmber,
                                          foregroundColor: TabbyColors.brandInk,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  30,
                                ),
                                itemCount: tab.entries.length > _historyLimit
                                    ? _historyLimit + 1
                                    : tab.entries.length,
                                itemBuilder: (context, index) {
                                  if (index == _historyLimit) {
                                    return TextButton(
                                      onPressed: () =>
                                          setState(() => _historyLimit += 50),
                                      child: const Text('Load older records'),
                                    );
                                  }
                                  final entry = tab.entries[index];
                                  return _buildLedgerEntryCard(
                                    context,
                                    ref,
                                    entry,
                                  );
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
      ),
    );
  }

  Widget _buildLedgerEntryCard(
    BuildContext context,
    WidgetRef ref,
    LedgerEntry entry,
  ) {
    final dateFormat = DateFormat('HH:mm - MMM d');
    final currentUser = ref.watch(currentUserProvider);
    final isPayment = entry.isPayment;
    final isMyEntry =
        entry.paidByUserId == currentUser.id ||
        (SupabaseConfig.isInitialized &&
            entry.paidByUserId == SupabaseConfig.currentUserId);
    final amountPrefix = isPayment ? '+' : (isMyEntry ? '+' : '-');
    final amountColor = isPayment
        ? TabbyPalette.of(context).positiveText
        : (isMyEntry
              ? TabbyPalette.of(context).text
              : TabbyPalette.of(context).link);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TabbyPalette.of(context).border),
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
                      ? TabbyPalette.of(context).soft
                      : TabbyPalette.of(context).accentTint,
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
                        ? TabbyPalette.of(context).link
                        : TabbyPalette.of(context).link,
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TabbyPalette.of(context).text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateFormat.format(entry.date),
                      style: TextStyle(
                        fontSize: 11,
                        color: TabbyPalette.of(context).link,
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
                color: TabbyPalette.of(context).border,
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
                      style: TextStyle(
                        fontSize: 11,
                        color: TabbyPalette.of(context).text,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _buildStatusBadge(
                      context,
                      entry.status,
                      isPayment,
                      revision: entry.revision,
                    ),
                  ],
                ),
              ),
              // Column Divider
              Container(
                height: 28,
                width: 1,
                color: TabbyPalette.of(context).border,
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

  Widget _buildStatusBadge(
    BuildContext context,
    TransactionStatus status,
    bool isPayment, {
    ExpenseRevision? revision,
  }) {
    Color bg;
    Color text;
    String label;

    if (isPayment) {
      if (status == TransactionStatus.settled) {
        bg = TabbyPalette.of(context).soft;
        text = TabbyPalette.of(context).positiveText;
        label = 'Payment Settled';
      } else if (status == TransactionStatus.cancelled) {
        bg = TabbyPalette.of(context).canvas;
        text = TabbyPalette.of(context).secondaryText;
        label = 'Payment Rejected';
      } else {
        bg = TabbyPalette.of(context).accentTint;
        text = TabbyPalette.of(context).link;
        label = 'Awaiting Confirmation';
      }
    } else {
      switch (status) {
        case TransactionStatus.pending:
          bg = TabbyPalette.of(context).pendingTint;
          text = TabbyPalette.of(context).warningText;
          label = 'Recorded';
          break;
        case TransactionStatus.acknowledged:
          bg = TabbyPalette.of(context).successTint;
          text = TabbyPalette.of(context).text;
          label = 'Recorded';
          break;
        case TransactionStatus.paymentSubmitted:
          bg = TabbyPalette.of(context).accentTint;
          text = TabbyPalette.of(context).link;
          label = 'Payment Sent';
          break;
        case TransactionStatus.settled:
          bg = TabbyPalette.of(context).soft;
          text = TabbyPalette.of(context).positiveText;
          label = 'Settled';
          break;
        case TransactionStatus.cancelled:
          bg = TabbyPalette.of(context).errorTint;
          text = TabbyPalette.of(context).errorText;
          label = 'Cancelled';
          break;
        case TransactionStatus.disputed:
          bg = TabbyPalette.of(context).pendingTint;
          text = TabbyPalette.of(context).warningText;
          label = 'Disputed';
          break;
      }
    }

    if (!isPayment && revision?.role == 'original') label = 'Revised original';
    if (!isPayment && revision?.role == 'reversal') label = 'Reversal';
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
    final session = SupabaseConfig.captureSession();
    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final friendName = tab.counterpart.displayName;
        final expenseTitle = tab.isGroupTab
            ? (tab.groupName ?? (tab.entries.firstOrNull?.title ?? 'Group Tab'))
            : (tab.entries.firstOrNull?.title ?? 'Shared Expense');
        final firstEntry = tab.entries.firstOrNull;
        final categoryIcon = firstEntry?.isPayment == true
            ? Icons.payments_rounded
            : (firstEntry?.category.icon ?? Icons.receipt_long_rounded);

        return AccountDraftGuard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: TabbyPalette.of(context).surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
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
                          'Send Friendly Reminder',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
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
                  TabbyMascotWidget(
                    emotion: MascotEmotion.gentleNudge,
                    size: 52,
                    customMessage:
                        'Send $friendName a reminder in Tabby. Device alerts depend on their notification settings.',
                  ),
                  const SizedBox(height: 16),
                  // Structured Intended Reminder Information Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: TabbyPalette.of(context).canvas,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: TabbyPalette.of(context).border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Recipient Profile Header
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: tab.isGroupTab
                                  ? TabbyPalette.of(context).soft
                                  : TabbyPalette.of(context).accentTint,
                              child: Text(
                                tab.isGroupTab
                                    ? 'G'
                                    : (friendName.isNotEmpty
                                          ? friendName
                                                .substring(0, 1)
                                                .toUpperCase()
                                          : '?'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: tab.isGroupTab
                                      ? TabbyPalette.of(context).link
                                      : TabbyPalette.of(context).link,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'RECIPIENT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyPalette.of(context)
                                          .secondaryText,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    friendName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: TabbyPalette.of(context).text,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: TabbyPalette.of(context).accentTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_outline_rounded,
                                    size: 13,
                                    color: TabbyPalette.of(context).link,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Debtor',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyPalette.of(context).link,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(
                            height: 1,
                            color: TabbyPalette.of(context).border,
                          ),
                        ),
                        // Expense Title & Amount
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TAB / EXPENSE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyPalette.of(context)
                                          .secondaryText,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        categoryIcon,
                                        size: 16,
                                        color: TabbyPalette.of(context).link,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          expenseTitle,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: TabbyPalette.of(context)
                                                .text,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'AMOUNT DUE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: TabbyPalette.of(context)
                                        .secondaryText,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  CurrencyFormatter.formatCentavos(
                                    tab.netBalanceCentavos.abs(),
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: TabbyPalette.of(context).link,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Delivery Dispatch Info Banner
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: TabbyPalette.of(context).soft
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.notifications_active_rounded,
                                size: 15,
                                color: TabbyPalette.of(context).link,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your friend can see an accepted reminder in Tabby. Device delivery depends on their notification settings.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: TabbyPalette.of(context).text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TabbyButton(
                    label: 'Send In-App Reminder',
                    variant: TabbyButtonVariant.primary,
                    icon: const Icon(
                      Icons.notifications_active_rounded,
                      size: 18,
                      color: TabbyColors.surfaceWhite,
                    ),
                    onPressed: () async {
                      final messenger = TabbyFeedback.of(context);
                      final navigator = Navigator.of(context);
                      final route = ModalRoute.of(context);
                      messenger.clearSnackBars();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Waiting for reminder acceptance…'),
                        ),
                      );
                      final result = await ref
                          .read(tabbyProvider.notifier)
                          .sendGentleNudge(
                            tabId: tab.id,
                            friendName: friendName,
                            amountCentavos: tab.netBalanceCentavos,
                            recipientUserId: tab.counterpart.id,
                            description: expenseTitle,
                          );
                      if (!context.mounted ||
                          !SupabaseConfig.isCurrentSession(session)) {
                        return;
                      }
                      if (route?.isActive == true) {
                        if (route!.isCurrent) {
                          navigator.pop();
                        } else {
                          navigator.removeRoute(route);
                        }
                      }
                      messenger.clearSnackBars();
                      messenger.showSnackBar(
                        SnackBar(content: Text(result.message)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGroupObligations(
    BuildContext context,
    WidgetRef ref,
    BilateralTab tab,
  ) {
    showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      builder: (context) => AccountDraftGuard(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _groupObligations(context, ref, tab),
          ),
        ),
      ),
    );
  }

  Widget _groupObligations(
    BuildContext context,
    WidgetRef ref,
    BilateralTab tab,
  ) {
    if (tab.entries.any(
      (e) =>
          !e.isPayment &&
          e.status != TransactionStatus.cancelled &&
          e.participants.isEmpty,
    )) {
      return const Text('Refresh this group to load individual obligations.');
    }
    final obligations = groupObligations(tab);
    final actor = ref.watch(currentUserProvider).id;
    if (obligations.isEmpty) {
      return const Text('No outstanding group obligations.');
    }
    String name(String id) => id == actor
        ? 'You'
        : tab.members.where((m) => m.id == id).first.displayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Who owes whom',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        for (final obligation in obligations)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${name(obligation.payerId)} → ${name(obligation.recipientId)}: ${CurrencyFormatter.formatCentavos(obligation.amountCentavos)}',
                ),
                if (actor == obligation.payerId ||
                    actor == obligation.recipientId)
                  Builder(
                    builder: (context) {
                      final incoming = actor == obligation.recipientId;
                      final otherId = incoming
                          ? obligation.payerId
                          : obligation.recipientId;
                      final pairTab = tab.copyWith(
                        counterpart: tab.members.singleWhere(
                          (m) => m.id == otherId,
                        ),
                        netBalanceCentavos: incoming
                            ? obligation.amountCentavos
                            : -obligation.amountCentavos,
                      );
                      return Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            key: ValueKey(
                              'pair-info-${obligation.payerId}-${obligation.recipientId}',
                            ),
                            onPressed: () => PaymentMethodPaymentSheet.show(
                              context,
                              pairTab,
                            ),
                            child: const Text('Payment info'),
                          ),
                          TextButton(
                            key: ValueKey(
                              'pair-pay-${obligation.payerId}-${obligation.recipientId}',
                            ),
                            onPressed: () => _showSettlementModal(
                              context,
                              ref,
                              pairTab,
                              isPayingMe: incoming,
                            ),
                            child: Text(
                              incoming ? 'Record received cash' : 'I paid',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _showSettlementModal(
    BuildContext context,
    WidgetRef ref,
    BilateralTab tab, {
    required bool isPayingMe,
  }) {
    showTabbyFormPage<void>(
      context: context,
      builder: (_) => PaymentDraftForm(tab: tab, isPayingMe: isPayingMe),
    );
  }

  void _showEntryDetailsSheet(
    BuildContext context,
    WidgetRef ref,
    LedgerEntry entry,
  ) {
    final session = SupabaseConfig.captureSession();
    final candidates = ref
        .read(tabbyProvider)
        .tabs
        .where((t) => t.id == entry.tabId)
        .toList();
    final tab = candidates.isEmpty ? null : candidates.first;
    final owner = ref.read(currentUserProvider).id;
    final canChange =
        !entry.isPayment &&
        entry.revision?.role != 'reversal' &&
        tab != null &&
        !tab.isLocalOnly &&
        entry.participants.isNotEmpty &&
        entry.participants.any((p) => p.userId == owner);
    final dateFormat = DateFormat('MMMM d, yyyy • h:mm a');
    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return AccountDraftGuard(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: TabbyPalette.of(context).surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
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
                          entry.isPayment
                              ? 'Payment Details'
                              : 'Expense Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
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
                      if (entry.isPayment &&
                          (entry.status == TransactionStatus.paymentSubmitted ||
                              entry.status == TransactionStatus.pending ||
                              entry.status == TransactionStatus.settled))
                        TabbyMascotWidget.art(
                          pose: entry.status == TransactionStatus.settled
                              ? TabbyMascotPose.celebrating
                              : TabbyMascotPose.waiting,
                          size: 52,
                        )
                      else
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: entry.isPayment
                                ? TabbyPalette.of(context).soft
                                : TabbyPalette.of(context).accentTint,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Icon(
                              entry.isPayment
                                  ? (entry.paymentMethod?.iconData ??
                                        Icons.payments_rounded)
                                  : entry.category.icon,
                              color: entry.isPayment
                                  ? TabbyPalette.of(context).link
                                  : TabbyPalette.of(context).link,
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: TabbyPalette.of(context).text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateFormat.format(entry.date),
                              style: TextStyle(
                                fontSize: 12,
                                color: TabbyPalette.of(context).secondaryText,
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
                      color: TabbyPalette.of(context).soft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Amount',
                              style: TextStyle(
                                fontSize: 13,
                                color: TabbyPalette.of(context).secondaryText,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.formatCentavos(
                                entry.totalAmountCentavos,
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: TabbyPalette.of(context).text,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Paid By',
                              style: TextStyle(
                                fontSize: 13,
                                color: TabbyPalette.of(context).secondaryText,
                              ),
                            ),
                            Text(
                              entry.paidByName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: TabbyPalette.of(context).text,
                              ),
                            ),
                          ],
                        ),
                        if (!entry.isPayment && entry.participants.isNotEmpty)
                          ...entry.participants.map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Expanded(child: Text("${p.name}'s share")),
                                  Text(
                                    CurrencyFormatter.formatCentavos(
                                      p.shareAmountCentavos,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (!entry.isPayment && entry.participants.isEmpty) ...[
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Your Share',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: TabbyPalette.of(context).secondaryText,
                                ),
                              ),
                              Text(
                                CurrencyFormatter.formatCentavos(
                                  entry.myShareCentavos,
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyPalette.of(context).text,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Their Share',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: TabbyPalette.of(context).secondaryText,
                                ),
                              ),
                              Text(
                                CurrencyFormatter.formatCentavos(
                                  entry.counterpartShareCentavos,
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyPalette.of(context).text,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (entry.isPayment &&
                            entry.status ==
                                TransactionStatus.paymentSubmitted &&
                            entry.recipient?.kind == PartyKind.user &&
                            entry.recipient?.id ==
                                ref.read(currentUserProvider).id)
                          PaymentDecisionActions(paymentId: entry.id),
                        if (entry.rejectionReason != null)
                          Text('Rejection reason: ${entry.rejectionReason}'),
                        if (entry.paymentReference?.isNotEmpty == true)
                          Text('Payment reference: ${entry.paymentReference}'),
                        if (entry.paymentMethod != null) ...[
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Payment Rail',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: TabbyPalette.of(context).secondaryText,
                                ),
                              ),
                              Text(
                                entry.paymentMethod!.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyPalette.of(context).link,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (entry.dueDate != null) ...[
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Due Date',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: TabbyPalette.of(context).secondaryText,
                                ),
                              ),
                              Text(
                                DateFormat('MMMM d, yyyy')
                                    .format(entry.dueDate!),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyPalette.of(context).text,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Receipt / Attachment',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: TabbyPalette.of(context).secondaryText,
                                ),
                              ),
                            ),
                            Text(
                              entry.receiptUrl != null &&
                                      entry.receiptUrl!.isNotEmpty
                                  ? 'Attached'
                                  : 'None',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color:
                                    entry.receiptUrl != null &&
                                        entry.receiptUrl!.isNotEmpty
                                    ? TabbyPalette.of(context).link
                                    : TabbyPalette.of(context).secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (entry.revision != null) ...[
                    Text('Change reason: ${entry.revision!.reason}'),
                    SelectableText(
                      'Original expense: ${entry.revision!.originalId}',
                    ),
                    SelectableText(
                      'Change reference: ${entry.revision!.changeId}',
                    ),
                    if (entry.revision!.parentOriginalId != null &&
                        entry.revision!.parentOriginalId !=
                            entry.revision!.originalId)
                      SelectableText(
                        'Earlier original: ${entry.revision!.parentOriginalId}; earlier change: ${entry.revision!.parentChangeId}',
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (M2Capabilities.expenseReview && !entry.isPayment)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Expense review'),
                      onPressed: () {
                        if (!SupabaseConfig.isCurrentSession(session)) return;
                        Navigator.of(sheetContext).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ExpenseReviewScreen(
                              transactionId: entry.id,
                              queue: ref
                                  .read(tabbyProvider.notifier)
                                  .m2Commands,
                            ),
                          ),
                        );
                      },
                    ),
                  if (canChange)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Expense changes'),
                      onPressed: () {
                        if (!SupabaseConfig.isCurrentSession(session)) return;
                        final service = ExpenseChanges.production();
                        Navigator.of(sheetContext).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AccountDraftGuard(
                              child: ExpenseChangeScreen(
                                entry: entry,
                                service: service,
                                refreshHistory: () => ref
                                    .read(tabbyProvider.notifier)
                                    .refreshTabs(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  if (entry.receiptHistory.length > 1)
                    ...entry.receiptHistory
                        .asMap()
                        .entries
                        .where((revision) => revision.value != entry.receiptUrl)
                        .map(
                          (revision) => TextButton(
                            onPressed: () => _showReceiptPreviewSheet(
                              context,
                              entry.copyWith(receiptUrl: revision.value),
                            ),
                            child: Text('Earlier receipt ${revision.key + 1}'),
                          ),
                        ),
                  if (entry.receiptUrl == null || entry.receiptUrl!.isEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _attachReceiptPhoto(
                        context,
                        sheetContext,
                        ref,
                        entry,
                      ),
                      icon: const Icon(
                        Icons.add_photo_alternate_rounded,
                        size: 18,
                      ),
                      label: const Text('Attach Receipt Photo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TabbyPalette.of(context).text,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: TabbyPalette.of(context).surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: TabbyColors.brandAmber.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_outlined,
                                color: TabbyPalette.of(context).link,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Receipt attached (tap to view)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: TabbyPalette.of(context).link,
                                  ),
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
          ),
        );
      },
    );
  }

  /// Recover or select an image for this exact entry, retain owned bytes, then
  /// hand the stable receipt operation to the durable executor.
  Future<void> _attachReceiptPhoto(
    BuildContext context,
    BuildContext sheetContext,
    WidgetRef ref,
    LedgerEntry entry,
  ) async {
    final messenger = TabbyFeedback.of(context);
    final owner = ref.read(currentUserProvider).id;
    final session = SupabaseConfig.captureSession();
    final purpose = 'receipt:${entry.tabId}:${entry.id}';
    bool active() =>
        context.mounted &&
        SupabaseConfig.isCurrentSession(session) &&
        ref.read(currentUserProvider).id == owner;
    const store = FormDraftStore();
    try {
      var file = await ReceiptAttachmentService.recovery.restored(
        owner,
        purpose,
      );
      if (!active() || !context.mounted) return;
      if (file == null) {
        final source = await ReceiptSourceSheet.show(context);
        if (source == null || !active()) return;
        file = await ReceiptAttachmentService.pickImage(
          source,
          ownerId: owner,
          purpose: purpose,
        );
      }
      if (file == null || !active()) return;
      var draft = await store.read(owner, purpose);
      if (!active()) return;
      if (draft == null || draft['image'] != file.path) {
        final reference = await ReceiptBlobStore.save(
          await file.readAsBytes(),
          ownerId: owner,
        );
        draft = {
          'image': file.path,
          'reference': reference,
          'operation': const Uuid().v4(),
        };
        await store.write(owner, purpose, draft);
      }
      if (!active()) return;
      await ref
          .read(tabbyProvider.notifier)
          .attachReceiptToEntry(
            operationId: draft['operation'] as String,
            tabId: entry.tabId,
            entryId: entry.id,
            receiptUrl: draft['reference'] as String,
          );
      if (!active()) return;
      await ReceiptAttachmentService.recovery.acknowledge(owner, purpose, file);
      await store.remove(owner, purpose);
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Receipt image attached to transaction successfully!',
            ),
          ),
        );
    } catch (_) {
      if (active()) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Receipt could not be attached. Your image draft is kept; reopen this receipt and retry.',
              ),
            ),
          );
      }
    }
  }

  void _showReceiptsSheet(
    BuildContext context,
    BilateralTab tab,
    WidgetRef ref,
  ) {
    final entriesWithReceipts = tab.entries
        .where((e) => e.receiptUrl != null && e.receiptUrl!.isNotEmpty)
        .toList();

    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AccountDraftGuard(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: TabbyPalette.of(context).surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Shared Media & Receipts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyPalette.of(context).text,
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
                  style: TextStyle(
                    fontSize: 12,
                    color: TabbyPalette.of(context).secondaryText,
                  ),
                ),
                const SizedBox(height: 16),
                if (entriesWithReceipts.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: TabbyPalette.of(context).soft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: TabbyPalette.of(context).secondaryText,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No Receipts Attached Yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Attach bill photos, receipts, or payment screenshots to keep proof organized.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyPalette.of(context).secondaryText,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (tab.entries.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: () => _attachReceiptPhoto(
                              context,
                              context,
                              ref,
                              tab.entries.first,
                            ),
                            icon: const Icon(
                              Icons.add_a_photo_outlined,
                              size: 16,
                            ),
                            label: const Text('Attach to Latest Transaction'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TabbyColors.brandAmber,
                              foregroundColor: TabbyColors.brandInk,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
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
                            color: TabbyPalette.of(context).surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: TabbyPalette.of(context).border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: TabbyPalette.of(context).soft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.receipt_rounded,
                                  color: TabbyPalette.of(context).link,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: TabbyPalette.of(context).text,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${DateFormat('MMM d, yyyy').format(item.date)} • ${CurrencyFormatter.formatCentavos(item.totalAmountCentavos)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: TabbyPalette.of(context)
                                            .secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.visibility_outlined,
                                  color: TabbyPalette.of(context).link,
                                  size: 20,
                                ),
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
          ),
        );
      },
    );
  }

  /// Resolves a stored receipt reference into a displayable image URL.
  ///
  /// Remote URLs pass through unchanged. Relative Supabase Storage paths
  /// (`<userId>/<entryKey>.<ext>`) are converted into short-lived signed URLs
  /// so private proof images stay protected (ADR-011). Returns null when the
  /// reference is a local device file path or cannot be signed.
  static Future<String?> resolveReceiptImageUrl(String receiptUrl) async {
    if (receiptUrl.isEmpty) return null;
    if (receiptUrl.startsWith('http')) return receiptUrl;

    final looksLikeLocalFile =
        receiptUrl.contains('\\') ||
        receiptUrl.startsWith('/') ||
        receiptUrl.contains(':/') ||
        receiptUrl.toLowerCase().contains(':\\\\');
    final looksLikeStoragePath =
        !looksLikeLocalFile && receiptUrl.contains('/');

    if (looksLikeStoragePath &&
        SupabaseConfig.isInitialized &&
        SupabaseConfig.currentUserId != null) {
      try {
        return await SupabaseConfig.paymentProofsBucket.createSignedUrl(
          receiptUrl,
          600,
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Fallback tile shown when a receipt image cannot be rendered.
  static Widget _receiptFallbackTile(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).soft,
        shape: BoxShape.rectangle,
      ),
      child: Center(
        child: Icon(
          Icons.receipt_long_rounded,
          size: 40,
          color: TabbyPalette.of(context).link,
        ),
      ),
    );
  }

  void _showReceiptPreviewSheet(BuildContext context, LedgerEntry entry) {
    final session = SupabaseConfig.captureSession();
    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AccountDraftGuard(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: TabbyPalette.of(context).surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
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
                          Text(
                            'Receipt Preview',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: TabbyPalette.of(context).text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.title,
                            style: TextStyle(
                              fontSize: 12,
                              color: TabbyPalette.of(context).secondaryText,
                            ),
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
                      color: TabbyPalette.of(context).canvas,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: TabbyPalette.of(context).border,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child:
                                ReceiptBlobStore.isPending(
                                  entry.receiptUrl ?? '',
                                )
                                ? FutureBuilder<Uint8List?>(
                                    future: ReceiptBlobStore.read(
                                      entry.receiptUrl!,
                                      ownerId: ProviderScope.containerOf(
                                        context,
                                      ).read(currentUserProvider).id,
                                    ),
                                    builder: (_, snapshot) =>
                                        snapshot.data == null
                                        ? _receiptFallbackTile(context)
                                        : Image.memory(
                                            snapshot.data!,
                                            height: 180,
                                            width: double.infinity,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                _receiptFallbackTile(context),
                                          ),
                                  )
                                : FutureBuilder<String?>(
                                    future: resolveReceiptImageUrl(
                                      entry.receiptUrl ?? '',
                                    ),
                                    builder: (context, snapshot) {
                                      final remoteUrl = snapshot.data;
                                      if (remoteUrl != null) {
                                        return Image.network(
                                          remoteUrl,
                                          width: double.infinity,
                                          height: 180,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _receiptFallbackTile(context),
                                        );
                                      }
                                      final receiptPath =
                                          entry.receiptUrl ?? '';
                                      final isLocalFile =
                                          receiptPath.contains('\\') ||
                                          receiptPath.startsWith('/') ||
                                          receiptPath.contains(':/');
                                      if (isLocalFile) {
                                        return Image.file(
                                          File(receiptPath),
                                          width: double.infinity,
                                          height: 180,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _receiptFallbackTile(context),
                                        );
                                      }
                                      return _receiptFallbackTile(context);
                                    },
                                  ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            CurrencyFormatter.formatCentavos(
                              entry.totalAmountCentavos,
                            ),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: TabbyPalette.of(context).text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            DateFormat('MMMM d, yyyy • h:mm a')
                                .format(entry.date),
                            style: TextStyle(
                              fontSize: 12,
                              color: TabbyPalette.of(context).secondaryText,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: TabbyPalette.of(context).soft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 16,
                                  color: TabbyPalette.of(context).link,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Receipt attached',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyPalette.of(context).text,
                                    ),
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
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TabbyButton(
                        label: 'Save Image',
                        variant: TabbyButtonVariant.outline,
                        icon: Icon(
                          Icons.download_rounded,
                          size: 16,
                          color: TabbyPalette.of(context).text,
                        ),
                        onPressed: () async {
                          final messenger = TabbyFeedback.of(context);
                          final resolved = await resolveReceiptImageUrl(
                            entry.receiptUrl ?? '',
                          );
                          if (!context.mounted ||
                              !SupabaseConfig.isCurrentSession(session)) {
                            return;
                          }
                          if (resolved != null) {
                            final opened = await launchUrl(
                              Uri.parse(resolved),
                              mode: LaunchMode.externalApplication,
                            );
                            if (!context.mounted ||
                                !SupabaseConfig.isCurrentSession(session)) {
                              return;
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  opened
                                      ? 'Receipt image opened. Save it from there.'
                                      : 'Could not open the receipt image.',
                                ),
                              ),
                            );
                            return;
                          }
                          final localPath = entry.receiptUrl ?? '';
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                localPath.isEmpty
                                    ? 'No receipt image is attached.'
                                    : 'Receipt stored on this device: $localPath',
                              ),
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
          ),
        );
      },
    );
  }
}
