import '../../../shared/widgets/tabby_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/session_scope.dart';
import '../../../core/config/supabase_config.dart';
import '../application/tabby_providers.dart';
import '../domain/ledger_validation.dart';

class PaymentDecisionActions extends ConsumerStatefulWidget {
  const PaymentDecisionActions({super.key, required this.paymentId});
  final String paymentId;
  @override
  ConsumerState<PaymentDecisionActions> createState() =>
      _PaymentDecisionActionsState();
}

class _PaymentDecisionActionsState
    extends ConsumerState<PaymentDecisionActions> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  late final SessionStamp _session;
  bool get _current => mounted && SupabaseConfig.isCurrentSession(_session);

  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.captureSession();
  }
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _decide(bool confirm) async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = TabbyFeedback.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    try {
      await ref.read(tabbyProvider.notifier).decidePayment(widget.paymentId,
          confirm: confirm, reason: _reason.text);
      if (!_current) return;
      if (route?.isActive == true) {
        if (route!.isCurrent) {
          navigator.pop();
        } else {
          navigator.removeRoute(route);
        }
      }
      messenger.showSnackBar(SnackBar(
          content: Text(confirm ? 'Payment confirmed.' : 'Payment rejected.')));
    } catch (error) {
      if (_current) {
        setState(() => _error = error is TabValidationException
            ? error.message
            : 'The decision could not be saved. Please try again.');
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(
            controller: _reason,
            maxLength: 500,
            decoration: InputDecoration(
                labelText: 'Reason if rejecting', errorText: _error)),
        Row(children: [
          Expanded(
              child: FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  child: const Text('Confirm Payment'))),
          const SizedBox(width: 8),
          Expanded(
              child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Reject Payment'))),
        ]),
        if (_busy) const LinearProgressIndicator(),
      ]);
}
