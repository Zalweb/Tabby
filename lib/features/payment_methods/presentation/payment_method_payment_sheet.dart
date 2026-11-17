import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/theme/motion_preferences.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/session_scope.dart';
import '../../../core/widgets/account_draft_guard.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../core/config/supabase_config.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../../tabs/domain/models.dart' show BilateralTab, TabbyUser;
import '../application/payment_methods_provider.dart';
import '../domain/payment_method.dart';
import 'receiving_qr_image.dart';

class PaymentMethodPaymentSheet extends ConsumerStatefulWidget {
  const PaymentMethodPaymentSheet({super.key, required this.tab});

  final BilateralTab tab;

  static Future<void> show(BuildContext context, BilateralTab tab) {
    return showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentMethodPaymentSheet(tab: tab),
    );
  }

  @override
  ConsumerState<PaymentMethodPaymentSheet> createState() =>
      _PaymentMethodPaymentSheetState();
}

class _PaymentMethodPaymentSheetState
    extends ConsumerState<PaymentMethodPaymentSheet>
    with WidgetsBindingObserver {
  late final SessionStamp _session;
  bool get _current => mounted && SupabaseConfig.isCurrentSession(_session);
  BilateralTab get tab => widget.tab;
  Timer? _refreshTimer;
  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.captureSession();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refresh(),
    );
  }

  void _refresh() {
    if (!_current) return;
    ref.invalidate(tabPaymentMethodsProvider);
    if (tab.netBalanceCentavos > 0) {
      ref
          .read(
            paymentMethodsProvider(ref.read(currentUserProvider).id).notifier,
          )
          .load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const AccountDraftGuard(child: SizedBox.shrink());
    final currentUser = ref.watch(currentUserProvider);
    final isTheyOwe = tab.netBalanceCentavos > 0;
    final payeeUserId = isTheyOwe ? currentUser.id : tab.counterpart.id;
    final session = SupabaseConfig.captureSession();
    final request = TabPaymentMethodRequest(
      tab.id,
      payeeUserId,
      sessionKey: '${session.accountId}:${session.generation}',
    );
    final paymentMethods = ref.watch(tabPaymentMethodsProvider(request));
    final fallbackUser = isTheyOwe ? currentUser : tab.counterpart;
    final ownerMethods = isTheyOwe
        ? ref.watch(paymentMethodsProvider(currentUser.id)).methods
        : const <PaymentMethod>[];

    return AccountDraftGuard(
      child: Material(
        color: TabbyPalette.of(context).surface,
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh payment methods',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose a saved payment method to settle this tab.',
                    style: TextStyle(
                      fontSize: 12,
                      color: TabbyPalette.of(context).secondaryText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (tab.netBalanceCentavos == 0)
                    const _NoPaymentDue()
                  else
                    paymentMethods.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(28),
                        child: Column(
                          children: [
                            TabbyMascotWidget.art(
                              pose: TabbyMascotPose.thinking,
                              size: 72,
                            ),
                            SizedBox(height: 8),
                            Text('Loading payment methods...'),
                          ],
                        ),
                      ),
                      error: (_, __) => Column(
                        children: [
                          const TabbyMascotWidget.art(
                            pose: TabbyMascotPose.helpful,
                            size: 72,
                          ),
                          const Text('Could not refresh payment methods.'),
                          TextButton(
                            onPressed: _refresh,
                            child: const Text('Retry methods'),
                          ),
                        ],
                      ),
                      data: (methods) {
                        final visibleMethods = methods.isNotEmpty
                            ? methods
                            : (isTheyOwe
                                  ? ownerMethods
                                  : (SupabaseConfig.isInitialized
                                        ? const <PaymentMethod>[]
                                        : _legacyMethods(fallbackUser)));
                        if (visibleMethods.isEmpty) {
                          return _UnavailablePaymentMethods(
                            legacyUser: fallbackUser,
                          );
                        }
                        return Column(
                          children: visibleMethods
                              .map(
                                (method) => ReceivingMethodCard(
                                  key: ValueKey(method.id),
                                  method: method,
                                  reload: () async {
                                    final repository =
                                        SupabaseTabbyRepository.instance;
                                    final fresh = isTheyOwe
                                        ? await repository.fetchPaymentMethods(
                                            currentUser.id,
                                          )
                                        : await repository
                                              .fetchPaymentMethodsForTab(
                                                tabId: tab.id,
                                                payeeUserId: payeeUserId,
                                              );
                                    return fresh
                                        .where((m) => m.id == method.id)
                                        .firstOrNull;
                                  },
                                ),
                              )
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
        color: TabbyPalette.of(context).canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TabbyPalette.of(context).border),
      ),
      child: Text(
        'There is no payment due for this tab right now.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: TabbyPalette.of(context).secondaryText,
        ),
      ),
    );
  }
}

class ReceivingMethodCard extends StatefulWidget {
  const ReceivingMethodCard({
    super.key,
    required this.method,
    required this.reload,
  });

  final PaymentMethod method;
  final Future<PaymentMethod?> Function() reload;

  @override
  State<ReceivingMethodCard> createState() => ReceivingMethodCardState();
}

class ReceivingMethodCardState extends State<ReceivingMethodCard> {
  late PaymentMethod? _current = widget.method;
  late final SessionStamp _session;
  bool get _sessionCurrent =>
      mounted && SupabaseConfig.isCurrentSession(_session);
  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.captureSession();
    SupabaseConfig.sessionRevision.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!_sessionCurrent) setState(() => _current = null);
  }

  @override
  void dispose() {
    SupabaseConfig.sessionRevision.removeListener(_sessionChanged);
    super.dispose();
  }

  PaymentMethod get method => _current!;
  @override
  void didUpdateWidget(covariant ReceivingMethodCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sessionCurrent && oldWidget.method != widget.method) {
      _current = widget.method;
    }
  }

  Future<PaymentMethod?> _reload() async {
    if (!_sessionCurrent) return null;
    final session = SupabaseConfig.captureSession();
    final fresh = await widget.reload();
    if (!mounted) return null;
    if (!_sessionCurrent || !SupabaseConfig.isCurrentSession(session)) {
      setState(() => _current = null);
      return null;
    }
    setState(() => _current = fresh);
    return fresh;
  }

  @override
  Widget build(BuildContext context) {
    if (_current == null) {
      return const Text(
        'Receiving method no longer available. Refresh methods.',
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: TabbyPalette.of(context).canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: method.isDefault
              ? TabbyColors.brandAmber
              : TabbyPalette.of(context).border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: TabbyPalette.of(context).link,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    method.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (method.isDefault)
                  Text(
                    'Preferred',
                    style: TextStyle(
                      color: TabbyPalette.of(context).link,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: ReceivingQrImage(method: method, reload: _reload),
            ),
            if (method.accountLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      method.accountLabel,
                      style: TextStyle(
                        color: TabbyPalette.of(context).secondaryText,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy account details',
                    onPressed: () async {
                      if (!_sessionCurrent) return;
                      try {
                        await Clipboard.setData(
                          ClipboardData(text: method.accountLabel),
                        );
                        if (!context.mounted || !_sessionCurrent) return;
                        TabbyFeedback.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Payment details copied.'),
                          ),
                        );
                      } catch (_) {
                        if (!context.mounted || !_sessionCurrent) return;
                        TabbyFeedback.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not copy payment details. Please try again.',
                            ),
                          ),
                        );
                      }
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
        color: TabbyPalette.of(context).canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TabbyPalette.of(context).border),
      ),
      child: Text(
        legacyUser.gcashNumber.isEmpty && legacyUser.mayaNumber.isEmpty
            ? 'No payment QR has been added for this tab yet.'
            : 'Payment QR options are unavailable right now. You can still send payment proof after settling.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: TabbyPalette.of(context).secondaryText,
        ),
      ),
    );
  }
}
