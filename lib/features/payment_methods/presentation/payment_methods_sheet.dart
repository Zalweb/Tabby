import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../../../core/theme/motion_preferences.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/profile_setup_draft.dart';

import '../../../core/services/receipt_attachment_service.dart';
import '../../../core/services/form_draft_store.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../../../core/services/qr_image_validator.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/payment_methods_provider.dart';
import '../domain/payment_method.dart';
import 'receiving_qr_image.dart';

class PaymentMethodsSheet extends ConsumerStatefulWidget {
  const PaymentMethodsSheet({super.key, required this.ownerUserId});

  final String ownerUserId;

  static Future<void> show(
    BuildContext context, {
    required String ownerUserId,
  }) async {
    await showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentMethodsSheet(ownerUserId: ownerUserId),
    );
  }

  @override
  ConsumerState<PaymentMethodsSheet> createState() =>
      _PaymentMethodsSheetState();
}

class _PaymentMethodsSheetState extends ConsumerState<PaymentMethodsSheet>
    with WidgetsBindingObserver {
  late final SessionStamp _session;
  bool get _current => mounted && SupabaseConfig.isCurrentSession(_session);
  String get ownerUserId => widget.ownerUserId;
  Timer? _refreshTimer;
  late final Future<bool> _retainedSetup;
  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.captureSession();
    _retainedSetup = ProfileSetupDraft.hasRetainedMethods(ownerUserId);
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
    if (_current) ref.read(paymentMethodsProvider(ownerUserId).notifier).load();
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
    final state = ref.watch(paymentMethodsProvider(ownerUserId));
    final notifier = ref.read(paymentMethodsProvider(ownerUserId).notifier);
    return AccountDraftGuard(
      child: Material(
        color: TabbyPalette.of(context).surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Payment Methods',
                          style: TextStyle(
                            fontSize: 20,
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
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    'People who owe you can see these options inside their tab.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: TabbyPalette.of(context).secondaryText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state.isLoading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          color: TabbyPalette.of(context).link,
                        ),
                      ),
                    )
                  else if (state.methods.isEmpty)
                    _EmptyMethodsCard(onAdd: () => _showEditor(context, ref))
                  else ...[
                    ...state.methods.map(
                      (method) => _PaymentMethodTile(
                        method: method,
                        onPreferred: () async {
                          if (!_current) return;
                          if (await notifier.setPreferred(method.id) &&
                              _current) {
                            ref.invalidate(tabPaymentMethodsProvider);
                          }
                        },
                        onDelete: () async {
                          if (!_current) return;
                          if (await notifier.remove(method.id) && _current) {
                            ref.invalidate(tabPaymentMethodsProvider);
                          }
                        },
                        onEdit: () => _showEditor(context, ref, method: method),
                        onPreview: () => _showPreview(context, ref, method),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _showEditor(context, ref),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Payment Method'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TabbyPalette.of(context).text,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.errorMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: TabbyPalette.of(context).errorText,
                      ),
                    ),
                  ],
                  FutureBuilder<bool>(
                    future: _retainedSetup,
                    builder: (context, snapshot) {
                      if (snapshot.data != true && !snapshot.hasError) {
                        return const SizedBox.shrink();
                      }
                      return TextButton(
                        onPressed: () {
                          if (!_current) return;
                          Navigator.pop(context);
                          context.go('/complete-profile?resume=true');
                        },
                        child: const Text('Finish receiving-method setup'),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref, {
    PaymentMethod? method,
  }) async {
    if (!_current) return;
    final provider = paymentMethodsProvider(ownerUserId);
    final notifier = ref.read(provider.notifier);
    await showTabbyFormPage<void>(
      context: context,
      builder: (_) => ReceivingMethodEditor(
        ownerId: ownerUserId,
        initial: method,
        onSave: (draft) async {
          if (!_current) return false;
          final saved = method == null
              ? await notifier.saveDraft(
                  draft,
                  makeDefault: ref.read(provider).methods.isEmpty,
                )
              : await notifier.updateDraft(method, draft);
          if (saved && context.mounted && _current) {
            ref.invalidate(tabPaymentMethodsProvider);
          }
          return saved;
        },
      ),
    );
  }

  void _showPreview(BuildContext context, WidgetRef ref, PaymentMethod method) {
    if (!_current) return;
    showDialog<void>(
      animationStyle: TabbyMotion.style(context),
      context: context,
      builder: (_) => AccountDraftGuard(
        child: AlertDialog(
          title: const Text('Receiving QR'),
          content: ReceivingQrImage(
            method: method,
            reload: () async {
              if (!_current) return null;
              final notifier = ref.read(
                paymentMethodsProvider(ownerUserId).notifier,
              );
              if (!await notifier.load()) throw StateError('Refresh failed');
              if (!_current) return null;
              return ref
                  .read(paymentMethodsProvider(ownerUserId))
                  .methods
                  .where((m) => m.id == method.id)
                  .firstOrNull;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMethodsCard extends StatelessWidget {
  const _EmptyMethodsCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).canvas,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TabbyPalette.of(context).border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.qr_code_2_rounded,
            size: 48,
            color: TabbyPalette.of(context).link,
          ),
          const SizedBox(height: 8),
          const Text(
            'No payment methods yet',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Upload a wallet receiving QR or add manual account details.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: TabbyPalette.of(context).secondaryText,
            ),
          ),
          const SizedBox(height: 14),
          TabbyButton(label: 'Add Payment Method', onPressed: onAdd),
        ],
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.onPreferred,
    required this.onDelete,
    required this.onPreview,
    required this.onEdit,
  });

  final PaymentMethod method;
  final VoidCallback onPreferred;
  final VoidCallback onDelete;
  final VoidCallback onPreview;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: method.isDefault
              ? TabbyColors.brandAmber
              : TabbyPalette.of(context).border,
        ),
      ),
      child: ListTile(
        onTap: onPreview,
        leading: CircleAvatar(
          backgroundColor: TabbyPalette.of(context).soft,
          child: Icon(
            method.qrUrl == null
                ? Icons.account_balance_wallet_outlined
                : Icons.qr_code_2_rounded,
            color: TabbyPalette.of(context).link,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                method.displayName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (method.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: TabbyPalette.of(context).soft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Preferred',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: TabbyPalette.of(context).link,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          method.accountLabel.isEmpty ? method.provider : method.accountLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'preferred') onPreferred();
            if (value == 'delete') onDelete();
            if (value == 'edit') onEdit();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'preferred',
              child: Text(method.isDefault ? 'Preferred' : 'Set as Preferred'),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Text('Edit or replace QR'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Remove')),
          ],
        ),
      ),
    );
  }
}

class ReceivingMethodEditor extends StatefulWidget {
  const ReceivingMethodEditor({
    super.key,
    this.initial,
    required this.onSave,
    this.staged = false,
    this.ownerId,
  });
  final String? ownerId;
  final bool staged;
  final PaymentMethod? initial;
  final Future<bool> Function(PaymentMethodDraft) onSave;

  @override
  State<ReceivingMethodEditor> createState() => ReceivingMethodEditorState();
}

class ReceivingMethodEditorState extends State<ReceivingMethodEditor> {
  final _nameController = TextEditingController();
  final _accountController = TextEditingController();
  String _provider = 'gcash';
  Uint8List? _qrBytes;
  String? _qrExtension;
  String? _qrMimeType;
  String? _error;

  bool _isSaving = false;
  bool _detailsConfirmed = false;
  late String _methodId;
  String _operationId = const Uuid().v4();
  bool _isCropping = false;
  bool _isAutoCropped = false;
  bool _discardChanges = false, _closing = false;
  late final String _owner, _purpose;
  late final SessionStamp _session;
  final _draftStore = const FormDraftStore();
  bool _ready = false, _restoring = false;
  Future<void>? _draftWork;
  String _baseline = '', _lastDraft = '';
  bool get _current =>
      mounted &&
      SupabaseConfig.isCurrentSession(_session) &&
      (!SupabaseConfig.isInitialized || SupabaseConfig.currentUserId == _owner);
  Map<String, dynamic> _snapshot() => {
    'method': _methodId,
    'operation': _operationId,
    'name': _nameController.text,
    'account': _accountController.text,
    'provider': _provider,
    'qr': _qrBytes == null ? null : base64Encode(_qrBytes!),
    'extension': _qrExtension,
    'mime': _qrMimeType,
    'expected_revision': widget.initial?.revision,
  };
  Future<void> _persist() async {
    if (!_ready || _restoring || !_current || _discardChanges) return;
    final value = _snapshot(), stamp = _snapshot().toString();
    if (stamp == _lastDraft) {
      await _draftWork;
      return;
    }
    _lastDraft = stamp;
    try {
      await (_draftWork = _draftStore.write(_owner, _purpose, value));
    } catch (_) {
      _lastDraft = '';
      if (_current) {
        super.setState(
          () => _error = 'Draft could not be saved. Keep editing and retry.',
        );
      }
      rethrow;
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _persist().catchError((Object _) {});
  }

  Future<void> _restore() async {
    try {
      final map = await _draftStore.read(_owner, _purpose);
      if (!_current) return;
      if (map != null) {
        if (map['expected_revision'] != widget.initial?.revision) {
          throw StateError('Method changed since draft');
        }
        _restoring = true;
        if (![
          'gcash',
          'maya',
          'bank_transfer',
          'paypal',
          'other',
        ].contains(map['provider'])) {
          throw const FormatException('Invalid provider draft');
        }
        _methodId = map['method'] as String;
        _operationId = map['operation'] as String;
        _nameController.text = map['name'] as String;
        _accountController.text = map['account'] as String;
        _provider = map['provider'] as String;
        _qrBytes = map['qr'] == null ? null : base64Decode(map['qr'] as String);
        _qrExtension = map['extension'] as String?;
        _qrMimeType = map['mime'] as String?;
      }
      _restoring = false;
      _ready = true;
      final file = await ReceiptAttachmentService.recovery.restored(
        _owner,
        _purpose,
      );
      if (file != null && _current) await _retainQr(file);
      if (_current) super.setState(() {});
    } catch (_) {
      _restoring = false;
      if (_current) {
        super.setState(
          () => _error = 'Your method draft could not be restored. Retry or discard it before editing.',
        );
      }
    }
  }

  Future<void> _retainQr(XFile file) async {
    final prepared = await QrImageValidator.prepare(await file.readAsBytes());
    if (!_current) return;
    _edited();
    _qrBytes = prepared.bytes;
    _qrExtension = 'png';
    _qrMimeType = 'image/png';
    _isAutoCropped = prepared.wasCropped;
    _detailsConfirmed = false;
    await _persist();
    await ReceiptAttachmentService.recovery.acknowledge(_owner, _purpose, file);
  }

  bool get _hasEdits =>
      _snapshot().toString() != _baseline || _detailsConfirmed;
  Future<void> _confirmClose() async {
    if (_closing || _isSaving || _isCropping) return;
    _closing = true;
    try {
      final discard = await showDialog<String>(
        animationStyle: TabbyMotion.style(context),
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('Keep this receiving-method draft?'),
          content: const Text(
            'These unsaved details have not been added to your setup.',
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
              onPressed: () => Navigator.pop(dialog, 'keep'),
              child: const Text('Keep draft'),
            ),
          ],
        ),
      );
      if (discard != null && _current) {
        if (discard == 'keep') {
          await _persist();
        } else {
          await _draftStore.remove(_owner, _purpose);
          await ReceiptAttachmentService.recovery.discard(_owner, _purpose);
        }
        if (!_current || !mounted) return;
        _discardChanges = true;
        Navigator.pop(context);
      }
    } finally {
      _closing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _owner =
        widget.ownerId ??
        SupabaseConfig.currentUserId ??
        widget.initial?.ownerUserId ??
        'offline';
    _purpose =
        'receiving:${widget.staged ? 'setup' : 'profile'}:${widget.initial?.id ?? 'new'}';
    _session = SupabaseConfig.captureSession();
    final initial = widget.initial;
    _methodId = initial?.id ?? const Uuid().v4();
    _nameController.text = initial?.displayName ?? '';
    _accountController.text = initial?.accountLabel ?? '';
    _provider = initial?.provider ?? 'gcash';
    _baseline = _snapshot().toString();
    _nameController.addListener(_edited);
    _accountController.addListener(_edited);
    _restore();
  }

  void _edited() {
    if (_restoring) return;
    _operationId = const Uuid().v4();
    if (widget.staged && mounted) {
      setState(() => _detailsConfirmed = false);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _save() async {
    if (!_ready || !_current || _isSaving) return;
    if (widget.staged &&
        ['gcash', 'maya'].contains(_provider) &&
        !_detailsConfirmed) {
      setState(() => _error = 'Confirm these are your receiving details.');
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a payment method name.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await _persist();
      if (!_current) return;
      final saved = await widget.onSave(
        PaymentMethodDraft(
          methodId: _methodId,
          operationId: _operationId,
          provider: _provider,
          displayName: _nameController.text.trim(),
          accountLabel: _accountController.text.trim(),
          qrBytes: _qrBytes,
          qrExtension: _qrExtension,
          qrMimeType: _qrMimeType,
        ),
      );
      if (!mounted) return;
      if (saved) {
        _discardChanges = true;
        try {
          await _draftStore.remove(_owner, _purpose);
        } catch (_) {}
        if (!_current || !mounted) return;
        Navigator.pop(context);
      } else {
        setState(
          () => _error = 'Could not verify the save. Your draft is kept. Refresh and try again.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AccountDraftGuard(
      child: PopScope<Object?>(
        canPop:
            _discardChanges ||
            (_ready && !_hasEdits && !_isSaving && !_isCropping),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _confirmClose();
        },
        child: Material(
          color: TabbyPalette.of(context).surface,
          borderRadius: isTabbyFormPage(context)
              ? BorderRadius.zero
              : const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: TabbyFormBody(
                header: TabbyFormHeader(
                  title: widget.initial == null
                      ? 'Add Payment Method'
                      : 'Edit Payment Method',
                  onBack: _isSaving || _isCropping
                      ? null
                      : () => Navigator.maybePop(context),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    if (widget.staged)
                      const Text(
                        'This adds a draft. Finish setup to save and share it.',
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: _provider,
                      isExpanded: true,
                      itemHeight: null,
                      disabledHint: Text(_provider),
                      decoration: const InputDecoration(labelText: 'Provider'),
                      items: const [
                        DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                        DropdownMenuItem(value: 'maya', child: Text('Maya')),
                        DropdownMenuItem(
                          value: 'bank_transfer',
                          child: Text('Bank Transfer'),
                        ),
                        DropdownMenuItem(
                          value: 'paypal',
                          child: Text('PayPal'),
                        ),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: _isSaving || !_ready
                          ? null
                          : (value) {
                              _edited();
                              setState(() => _provider = value ?? 'other');
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      enabled: !_isSaving && _ready,
                      decoration: const InputDecoration(
                        labelText: 'Payment method name',
                        hintText: 'My GCash QR',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _accountController,
                      enabled: !_isSaving && _ready,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Account number or note',
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Export your receiving QR from your wallet or bank, then upload it here. A readable QR does not verify the account or confirm payment.',
                      style: TextStyle(
                        fontSize: 12,
                        color: TabbyPalette.of(context).secondaryText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isCropping || _isSaving ? null : _pickQr,
                      icon: _isCropping
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_rounded),
                      label: Text(
                        _isCropping
                            ? 'Detecting and cropping QR...'
                            : (_qrBytes == null
                                  ? 'Upload wallet QR image'
                                  : 'Change QR screenshot'),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    if (widget.initial?.qrStoragePath != null &&
                        _qrBytes == null)
                      const Text(
                        'Your saved QR will be kept unless you upload a replacement.',
                      ),
                    if (_qrBytes != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                _qrBytes!,
                                width: 160,
                                height: 160,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: TabbyPalette.of(context).soft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isAutoCropped
                                        ? Icons.crop_rounded
                                        : Icons.check_circle_rounded,
                                    size: 14,
                                    color: TabbyPalette.of(context).link,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isAutoCropped
                                        ? 'Readable QR cropped from screenshot'
                                        : 'Readable QR image selected',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyPalette.of(context).text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: TabbyPalette.of(context).errorText,
                        ),
                      ),
                    ],
                    if (!_ready)
                      TextButton(
                        onPressed: _restore,
                        child: const Text('Retry draft'),
                      ),
                    const SizedBox(height: 16),
                    if (widget.staged && ['gcash', 'maya'].contains(_provider))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('These are my receiving details'),
                        value: _detailsConfirmed,
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(
                                () => _detailsConfirmed = value ?? false,
                              ),
                      ),
                    TabbyButton(
                      label: _isSaving
                          ? 'Saving...'
                          : (widget.staged
                                ? 'Add to setup'
                                : 'Save Payment Method'),
                      onPressed: _isCropping || _isSaving ? null : _save,
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

  Future<void> _pickQr() async {
    if (_isCropping || !_ready || !_current) return;
    setState(() {
      _isCropping = true;
      _error = null;
    });
    try {
      await _persist();
      if (!_current) return;
      final file = await ReceiptAttachmentService.pickImage(
        ImageSource.gallery,
        ownerId: _owner,
        purpose: _purpose,
      );
      if (file == null || !_current) return;
      await _retainQr(file);
      if (_current) setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is FormatException
            ? error.message
            : 'Unable to read QR image. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }
}
