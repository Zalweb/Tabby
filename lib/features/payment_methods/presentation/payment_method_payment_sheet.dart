import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart' show BilateralTab, TabbyUser;
import '../application/payment_methods_provider.dart';
import '../domain/payment_method.dart';

class PaymentMethodPaymentSheet extends ConsumerWidget {
  const PaymentMethodPaymentSheet({super.key, required this.tab});

  final BilateralTab tab;

  static Future<void> show(BuildContext context, BilateralTab tab) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentMethodPaymentSheet(tab: tab),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final isTheyOwe = tab.netBalanceCentavos > 0;
    final payeeUserId = isTheyOwe ? currentUser.id : tab.counterpart.id;
    final request = TabPaymentMethodRequest(tab.id, payeeUserId);
    final paymentMethods = ref.watch(tabPaymentMethodsProvider(request));
    final fallbackUser = isTheyOwe ? currentUser : tab.counterpart;
    final ownerMethods = isTheyOwe
        ? ref.watch(paymentMethodsProvider(currentUser.id)).methods
        : const <PaymentMethod>[];

    return Material(
      color: TabbyColors.surfaceWhite,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${isTheyOwe ? currentUser.displayName : tab.counterpart.displayName}\'s Payment Info',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Choose a saved payment method to settle this tab.',
                  style:
                      TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
                ),
                const SizedBox(height: 14),
                if (tab.netBalanceCentavos == 0)
                  const _NoPaymentDue()
                else
                  paymentMethods.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: CircularProgressIndicator(
                          color: TabbyColors.brandEmerald,
                        ),
                      ),
                    ),
                    error: (_, __) => _UnavailablePaymentMethods(
                      legacyUser: fallbackUser,
                    ),
                    data: (methods) {
                      final visibleMethods = methods.isNotEmpty
                          ? methods
                          : ownerMethods.isNotEmpty
                              ? ownerMethods
                              : _legacyMethods(fallbackUser);
                      if (visibleMethods.isEmpty) {
                        return _UnavailablePaymentMethods(
                          legacyUser: fallbackUser,
                        );
                      }
                      return Column(
                        children: visibleMethods
                            .map((method) => _PaymentChoiceTile(method: method))
                            .toList(),
                      );
                    },
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
        ),
      ),
    );
  }

  List<PaymentMethod> _legacyMethods(TabbyUser user) {
    return PaymentMethod.fromLegacyUser(user.toMap());
  }
}

class _NoPaymentDue extends StatelessWidget {
  const _NoPaymentDue();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TabbyColors.bgCanvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TabbyColors.borderMint),
      ),
      child: const Text(
        'There is no payment due for this tab right now.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
      ),
    );
  }
}

class _PaymentChoiceTile extends StatelessWidget {
  const _PaymentChoiceTile({required this.method});

  final PaymentMethod method;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: TabbyColors.bgCanvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: method.isDefault
              ? TabbyColors.brandEmerald
              : TabbyColors.borderMint,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: TabbyColors.brandEmerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(method.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (method.isDefault)
                  const Text(
                    'Preferred',
                    style: TextStyle(
                      color: TabbyColors.brandEmerald,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            if (method.qrUrl != null) ...[
              const SizedBox(height: 10),
              Center(
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: Image.network(
                    method.qrUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.qr_code_2_rounded,
                      size: 130,
                      color: TabbyColors.brandDarkTeal,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              const Center(
                child: Icon(Icons.qr_code_2_rounded,
                    size: 96, color: TabbyColors.brandDarkTeal),
              ),
            ],
            if (method.accountLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(method.accountLabel,
                        style:
                            const TextStyle(color: TabbyColors.textSecondary)),
                  ),
                  IconButton(
                    tooltip: 'Copy account details',
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: method.accountLabel));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Payment details copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 17),
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

class _UnavailablePaymentMethods extends StatelessWidget {
  const _UnavailablePaymentMethods({required this.legacyUser});

  final TabbyUser legacyUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TabbyColors.bgCanvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TabbyColors.borderMint),
      ),
      child: Text(
        legacyUser.gcashNumber.isEmpty && legacyUser.mayaNumber.isEmpty
            ? 'No payment QR has been added for this tab yet.'
            : 'Payment QR options are unavailable right now. You can still send payment proof after settling.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
      ),
    );
  }
}
