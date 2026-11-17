import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/theme/motion_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../application/payment_methods_provider.dart';
import 'payment_method_payment_sheet.dart';

/// Read-only profile view; database RLS authorizes the current caller.
class FriendReceivingMethodsSheet extends ConsumerStatefulWidget {
  const FriendReceivingMethodsSheet(
      {super.key, required this.userId, required this.displayName});
  final String userId;
  final String displayName;
  static Future<void> show(BuildContext context,
          {required String userId, required String displayName}) =>
      showTabbyBottomSheet<void>(
          sheetAnimationStyle: TabbyMotion.style(context),
          context: context,
          isScrollControlled: true,
          builder: (_) => FriendReceivingMethodsSheet(
              userId: userId, displayName: displayName));
  @override
  ConsumerState<FriendReceivingMethodsSheet> createState() =>
      _FriendReceivingMethodsSheetState();
}

class _FriendReceivingMethodsSheetState
    extends ConsumerState<FriendReceivingMethodsSheet>
    with WidgetsBindingObserver {
  late final SessionStamp _session;
  bool get _current => mounted && SupabaseConfig.isCurrentSession(_session);
  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.captureSession();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    if (!_current) return;
    ref.read(paymentMethodsProvider(widget.userId).notifier).load();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const AccountDraftGuard(child: SizedBox.shrink());
    final state = ref.watch(paymentMethodsProvider(widget.userId));
    return AccountDraftGuard(child: SafeArea(
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text("${widget.displayName}'s receiving methods",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: 'Refresh receiving methods',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh)),
                IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
              const Text(
                  'Use these details in your wallet. Viewing or sharing a QR never confirms payment.'),
              const SizedBox(height: 12),
              if (state.isLoading)
                const CircularProgressIndicator()
              else if (state.errorMessage != null)
                Column(children: [
                  Text(state.errorMessage!),
                  TextButton(
                      onPressed: _refresh, child: const Text('Retry methods'))
                ])
              else if (state.methods.isEmpty)
                const Text('No active receiving methods are available to you.')
              else
                ...state.methods.map((method) => ReceivingMethodCard(
                    key: ValueKey(method.id),
                    method: method,
                    reload: () async {
                      final methods = await SupabaseTabbyRepository.instance
                          .fetchPaymentMethods(widget.userId);
                      return methods
                          .where((m) => m.id == method.id)
                          .firstOrNull;
                    })),
            ]))));
  }
}
