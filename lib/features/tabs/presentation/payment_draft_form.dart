import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/widgets/account_draft_guard.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/session_scope.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/form_draft_store.dart';
import '../../../core/services/receipt_attachment_service.dart';
import '../../../core/services/receipt_blob_store.dart';
import '../../../core/theme/motion_preferences.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/receipt_source_sheet.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/tabby_providers.dart';
import '../domain/models.dart';

class PaymentDraftForm extends ConsumerStatefulWidget {
  const PaymentDraftForm({
    super.key,
    required this.tab,
    required this.isPayingMe,
  });
  final BilateralTab tab;
  final bool isPayingMe;
  @override
  ConsumerState<PaymentDraftForm> createState() => _PaymentDraftFormState();
}

class _PaymentDraftFormState extends ConsumerState<PaymentDraftForm> {
  final _store = const FormDraftStore();
  late final String _owner, _purpose;
  late final SessionStamp _session;
  late final TextEditingController _amount;
  final _reference = TextEditingController();
  String _operation = const Uuid().v4();
  String? _proof, _error;
  String? _proofImage;
  late PaymentMethod _method;
  bool _ready = false,
      _restoring = false,
      _busy = false,
      _attempted = false,
      _leaving = false,
      _done = false;
  String _baseline = '';
  bool get _current =>
      mounted &&
      SupabaseConfig.isCurrentSession(_session) &&
      ref.read(currentUserProvider).id == _owner;
  bool get _cashOnly => widget.tab.isTabOnlyParticipant || widget.isPayingMe;
  Map<String, dynamic> _snapshot() => {
    'operation': _operation,
    'amount': _amount.text,
    'reference': _reference.text,
    'proof': _proof,
    'proof_image': _proofImage,
    'method': _method.name,
    'attempted': _attempted,
  };
  bool get _dirty => _snapshot().toString() != _baseline;
  Future<void> _persist() async {
    if (_ready && !_restoring && _current && !_done) {
      await _store.write(_owner, _purpose, _snapshot());
    }
  }

  void _edited() {
    if (_restoring || !_ready || !_current) return;
    setState(() {});
    _persist().catchError((Object _) {
      if (_current) {
        setState(
          () => _error =
              'Draft could not be saved. Keep this form open and retry.',
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _owner = ref.read(currentUserProvider).id;
    _session = SupabaseConfig.captureSession();
    _purpose =
        'payment:${widget.tab.id}:${widget.tab.counterpart.id}:${widget.isPayingMe}';
    final cents = widget.tab.netBalanceCentavos.abs();
    _amount = TextEditingController(
      text: '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}',
    );
    _method = _cashOnly ? PaymentMethod.cash : PaymentMethod.gcash;
    _baseline = _snapshot().toString();
    _amount.addListener(_edited);
    _reference.addListener(_edited);
    _restore();
  }

  Future<void> _restore() async {
    try {
      final map = await _store.read(_owner, _purpose);
      if (!_current) return;
      _restoring = true;
      if (map != null) {
        _operation = map['operation'] as String;
        _amount.text = map['amount'] as String;
        _reference.text = map['reference'] as String;
        _proof = map['proof'] as String?;
        _proofImage = map['proof_image'] as String?;
        _method = PaymentMethod.values.byName(map['method'] as String);
        _attempted = map['attempted'] == true;
        if (_cashOnly && _method != PaymentMethod.cash) {
          throw const FormatException('Invalid cash draft');
        }
      }
      _restoring = false;
      _ready = true;
      final recovered = await ReceiptAttachmentService.recovery.restored(
        _owner,
        _purpose,
      );
      if (recovered != null && _current) await _retain(recovered);
      if (_current) setState(() {});
    } catch (_) {
      _restoring = false;
      if (_current) {
        setState(
          () => _error = 'Your payment draft could not be restored. Retry or discard the draft.',
        );
      }
    }
  }

  Future<void> _retain(XFile file) async {
    if (_proofImage == file.path && _proof != null) {
      await ReceiptAttachmentService.recovery.acknowledge(
        _owner,
        _purpose,
        file,
      );
      return;
    }
    final path = await ReceiptBlobStore.save(
      await file.readAsBytes(),
      ownerId: _owner,
    );
    if (!_current) return;
    _proof = path;
    _proofImage = file.path;
    await _persist();
    await ReceiptAttachmentService.recovery.acknowledge(_owner, _purpose, file);
  }

  Future<void> _pick() async {
    if (_busy || !_ready || _attempted) return;
    final source = await ReceiptSourceSheet.show(context);
    if (source == null || !_current) return;
    setState(() => _busy = true);
    try {
      await _persist();
      if (!_current) return;
      final file = await ReceiptAttachmentService.pickImage(
        source,
        ownerId: _owner,
        purpose: _purpose,
      );
      if (file != null && _current) await _retain(file);
    } catch (_) {
      if (_current) {
        setState(
          () => _error = 'The proof image could not be saved. Choose an image up to 5 MB and retry.',
        );
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy || _leaving || !_current) return;
    _leaving = true;
    try {
      final choice = await showDialog<String>(
        context: context,
        animationStyle: TabbyMotion.style(context),
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('Keep this payment draft?'),
          content: const Text(
            'Discarding this draft does not cancel a payment already submitted. Confirmed history stays in your tab.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, 'discard'),
              child: const Text('Discard draft'),
            ),
            TextButton(
              onPressed: _ready ? () => Navigator.pop(dialog, 'keep') : null,
              child: const Text('Keep draft'),
            ),
          ],
        ),
      );
      if (choice == null || !_current) return;
      if (choice == 'keep') {
        await _persist();
      } else {
        await _store.remove(_owner, _purpose);
        await ReceiptAttachmentService.recovery.discard(_owner, _purpose);
      }
      if (!mounted || !_current) return;
      _done = true;
      Navigator.pop(context);
    } catch (_) {
      if (_current) {
        setState(() => _error = 'Draft could not be saved. Please retry.');
      }
    } finally {
      _leaving = false;
    }
  }

  Future<void> _submit() async {
    if (_busy || !_ready || !_current) return;
    final cents = CurrencyFormatter.tryParseToCentavos(_amount.text);
    if (cents == null) {
      setState(
        () => _error = 'Enter a valid positive PHP amount with up to two decimals (maximum 999,999,999.99).',
      );
      return;
    }
    if (cents <= 0) {
      setState(() => _error = 'Please enter an amount greater than \u20B10.00');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _attempted = true;
    });
    final messenger = TabbyFeedback.of(context);
    try {
      await _persist();
      if (!_current) return;
      final notifier = ref.read(tabbyProvider.notifier);
      final reference = _reference.text.trim().isEmpty
          ? null
          : _reference.text.trim();
      if (widget.tab.isGroupTab) {
        await notifier.settleGroupPair(
          operationId: _operation,
          tabId: widget.tab.id,
          counterpartyUserId: widget.tab.counterpart.id,
          amountCentavos: cents,
          method: _method,
          isPayingMe: widget.isPayingMe,
          proofPath: _proof,
          paymentReference: reference,
        );
      } else {
        await notifier.settleTab(
          operationId: _operation,
          tabId: widget.tab.id,
          amountCentavos: cents,
          method: _method,
          isPayingMe: widget.isPayingMe,
          proofPath: _proof,
          paymentReference: reference,
        );
      }
      if (!mounted || !_current) return;
      _done = true;
      try {
        await _store.remove(_owner, _purpose);
      } catch (_) {}
      if (!mounted || !_current) return;
      Navigator.pop(context);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              widget.isPayingMe
                  ? 'Settlement recorded successfully!'
                  : 'Payment saved. Awaiting confirmation.',
            ),
          ),
        );
    } catch (_) {
      if (_current) {
        setState(() {
          _busy = false;
          _error =
              'Unable to save payment. Your draft is kept. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AccountDraftGuard(
    child: PopScope<Object?>(
      canPop: _done || (_ready && !_dirty && !_busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Material(
        color: TabbyPalette.of(context).surface,
        borderRadius: isTabbyFormPage(context)
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(32)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: TabbyFormBody(
              header: TabbyFormHeader(
                title: widget.isPayingMe
                    ? 'Record received cash'
                    : 'Record Settlement',
                onBack: _busy ? null : () => Navigator.maybePop(context),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const Text('Payment Method'),
                  Wrap(
                    spacing: 8,
                    children:
                        (_cashOnly
                                ? [PaymentMethod.cash]
                                : PaymentMethod.values)
                            .map(
                              (method) => ChoiceChip(
                                label: Text(method.label),
                                selected: _method == method,
                                onSelected: !_ready || _busy || _attempted
                                    ? null
                                    : (_) {
                                        setState(() => _method = method);
                                        _edited();
                                      },
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Amount (PHP)'),
                  TextField(
                    controller: _amount,
                    enabled: _ready && !_busy && !_attempted,
                    key: const ValueKey('payment-amount'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      prefixText: 'PHP ',
                      hintText: '0.00',
                    ),
                  ),
                  if (!widget.isPayingMe) ...[
                    TextField(
                      controller: _reference,
                      enabled: _ready && !_busy && !_attempted,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Payment reference (optional)',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: !_ready || _busy || _attempted ? null : _pick,
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        _proof == null
                            ? 'Attach payment proof (optional)'
                            : 'Payment proof attached',
                      ),
                    ),
                    const Text(
                      'Attachments do not confirm that payment was received.',
                    ),
                  ],
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: TabbyPalette.of(context).errorText,
                      ),
                    ),
                  if (!_ready)
                    TextButton(
                      onPressed: _restore,
                      child: const Text('Retry draft'),
                    ),
                  TabbyButton(
                    label: _cashOnly
                        ? 'Record Cash Payment'
                        : widget.isPayingMe
                        ? 'Confirm Payment'
                        : 'Submit Payment Proof',
                    isLoading: _busy,
                    onPressed: !_ready || _busy ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
