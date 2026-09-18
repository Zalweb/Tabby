import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/payment_methods_provider.dart';
import '../domain/payment_method.dart';

class PaymentMethodsSheet extends ConsumerWidget {
  const PaymentMethodsSheet({super.key, required this.ownerUserId});

  final String ownerUserId;

  static Future<void> show(
    BuildContext context, {
    required String ownerUserId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentMethodsSheet(ownerUserId: ownerUserId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(paymentMethodsProvider(ownerUserId));
    final notifier = ref.read(paymentMethodsProvider(ownerUserId).notifier);
    return Material(
      color: TabbyColors.surfaceWhite,
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
                    const Expanded(
                      child: Text(
                        'Payment Methods',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Text(
                  'People who owe you can see these options inside their tab.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: TabbyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                if (state.isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        color: TabbyColors.brandEmerald,
                      ),
                    ),
                  )
                else if (state.methods.isEmpty)
                  _EmptyMethodsCard(onAdd: () => _showEditor(context, ref))
                else ...[
                  ...state.methods.map(
                    (method) => _PaymentMethodTile(
                      method: method,
                      onPreferred: () => notifier.setPreferred(method.id),
                      onDelete: () => notifier.remove(method.id),
                      onPreview: () => _showPreview(context, method),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _showEditor(context, ref),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Payment Method'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TabbyColors.brandDarkTeal,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TabbyColors.alertRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditor(BuildContext context, WidgetRef ref) async {
    final provider = paymentMethodsProvider(ownerUserId);
    final result = await showModalBottomSheet<PaymentMethodDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _PaymentMethodEditor(),
    );
    if (result == null || !context.mounted) return;

    final makeDefault = ref.read(provider).methods.isEmpty;
    await ref.read(provider.notifier).saveDraft(
          result,
          makeDefault: makeDefault,
        );
  }

  void _showPreview(BuildContext context, PaymentMethod method) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(method.displayName),
        content: SizedBox(
          width: 240,
          height: 240,
          child: method.qrUrl == null
              ? const Center(
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    size: 140,
                    color: TabbyColors.brandDarkTeal,
                  ),
                )
              : Image.network(method.qrUrl!, fit: BoxFit.contain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
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
        color: TabbyColors.bgCanvas,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TabbyColors.borderMint),
      ),
      child: Column(
        children: [
          const Icon(Icons.qr_code_2_rounded,
              size: 48, color: TabbyColors.brandEmerald),
          const SizedBox(height: 8),
          const Text('No payment methods yet',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Add a QR code or payment account for easy settlement.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary)),
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
  });

  final PaymentMethod method;
  final VoidCallback onPreferred;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: method.isDefault
              ? TabbyColors.brandEmerald
              : TabbyColors.borderMint,
        ),
      ),
      child: ListTile(
        onTap: onPreview,
        leading: CircleAvatar(
          backgroundColor: TabbyColors.brandMintAccent,
          child: Icon(
            method.qrUrl == null
                ? Icons.account_balance_wallet_outlined
                : Icons.qr_code_2_rounded,
            color: TabbyColors.brandEmerald,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(method.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            if (method.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: TabbyColors.brandMintAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Preferred',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: TabbyColors.brandEmerald,
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
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'preferred',
              child: Text(method.isDefault ? 'Preferred' : 'Set as Preferred'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Remove')),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodEditor extends StatefulWidget {
  const _PaymentMethodEditor();

  @override
  State<_PaymentMethodEditor> createState() => _PaymentMethodEditorState();
}

class _PaymentMethodEditorState extends State<_PaymentMethodEditor> {
  final _nameController = TextEditingController();
  final _accountController = TextEditingController();
  String _provider = 'gcash';
  Uint8List? _qrBytes;
  String? _qrExtension;
  String? _qrMimeType;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TabbyColors.surfaceWhite,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Add Payment Method',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _provider,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: const [
                    DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                    DropdownMenuItem(value: 'maya', child: Text('Maya')),
                    DropdownMenuItem(
                        value: 'bank_transfer', child: Text('Bank Transfer')),
                    DropdownMenuItem(value: 'paypal', child: Text('PayPal')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) =>
                      setState(() => _provider = value ?? 'other'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Payment method name',
                    hintText: 'My GCash QR',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _accountController,
                  decoration: const InputDecoration(
                    labelText: 'Account number or note',
                    hintText: 'Optional',
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _pickQr,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(_qrBytes == null
                      ? 'Upload QR image'
                      : 'QR image selected'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: TabbyColors.alertRed)),
                ],
                const SizedBox(height: 16),
                TabbyButton(
                  label: 'Save Payment Method',
                  onPressed: () {
                    if (_nameController.text.trim().isEmpty) {
                      setState(() => _error = 'Enter a payment method name.');
                      return;
                    }
                    Navigator.pop(
                      context,
                      PaymentMethodDraft(
                        provider: _provider,
                        displayName: _nameController.text.trim(),
                        accountLabel: _accountController.text.trim(),
                        qrBytes: _qrBytes,
                        qrExtension: _qrExtension,
                        qrMimeType: _qrMimeType,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickQr() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      setState(() => _error = 'QR image must be 10 MB or smaller.');
      return;
    }

    final extension = file.path.split('.').last.toLowerCase();
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'heic'};
    if (!allowed.contains(extension)) {
      setState(() => _error = 'Use a JPG, PNG, WEBP, or HEIC image.');
      return;
    }

    setState(() {
      _qrBytes = bytes;
      _qrExtension = extension;
      _qrMimeType = extension == 'jpg' || extension == 'jpeg'
          ? 'image/jpeg'
          : 'image/$extension';
      _error = null;
    });
  }
}
