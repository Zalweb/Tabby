import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/qr_code_cropper.dart';
import '../../../core/services/tabby_api_services.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../payment_methods/domain/payment_method.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../../tabs/domain/models.dart';

/// Pre-configured setup item during new account profile completion.
class _SetupPaymentItem {
  _SetupPaymentItem({
    required this.provider,
    required this.displayName,
    required this.accountNumber,
    this.qrBytes,
    this.qrExtension,
    this.qrMimeType,
    this.generatedQrUrl,
    this.isAutoCropped = false,
    this.isDefault = false,
  });

  String provider;
  String displayName;
  String accountNumber;
  Uint8List? qrBytes;
  String? qrExtension;
  String? qrMimeType;
  String? generatedQrUrl;
  bool isAutoCropped;
  bool isDefault;

  PaymentMethodDraft toDraft() {
    return PaymentMethodDraft(
      provider: provider,
      displayName: displayName,
      accountLabel: accountNumber,
      qrBytes: qrBytes,
      qrExtension: qrExtension,
      qrMimeType: qrMimeType,
      generatedQrUrl: qrBytes == null ? generatedQrUrl : null,
    );
  }
}

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  // Step tracker: 0 = Social Identity, 1 = How Friends Pay You
  int _currentStep = 0;

  // Step 1 Controllers
  late final TextEditingController _nameController;
  final _phoneController = TextEditingController();
  String _selectedAvatar = 'asset:mascot';

  // Step 2 Payment Methods List
  final List<_SetupPaymentItem> _paymentMethods = [];

  bool _isSaving = false;
  bool _isValidatingPhone = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _nameController = TextEditingController(text: user.displayName);
    _phoneController.text = user.phone;
    if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      _selectedAvatar = user.avatarUrl!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Validates Step 1 and advances to Step 2
  Future<void> _goToStepTwo() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorText = 'Please enter your full name.');
      return;
    }
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _errorText = 'Please enter a valid mobile number.');
      return;
    }

    setState(() {
      _isValidatingPhone = true;
      _errorText = null;
    });

    try {
      final available = await SupabaseTabbyRepository.instance.isPhoneAvailable(
        phone: phone,
        currentUserId: SupabaseConfig.currentUserId,
      );
      if (!available) {
        if (!mounted) return;
        setState(() {
          _isValidatingPhone = false;
          _errorText =
              'This mobile number is already linked to another Tabby account. Please enter a different number.';
        });
        return;
      }
    } catch (e) {
      debugPrint('[CompleteProfileScreen] Phone validation warning: $e');
    }

    if (!mounted) return;

    setState(() {
      _isValidatingPhone = false;
      _errorText = null;
      // Pre-fill a default GCash entry using their phone number if none exist yet
      if (_paymentMethods.isEmpty) {
        _paymentMethods.add(
          _SetupPaymentItem(
            provider: 'gcash',
            displayName: 'GCash',
            accountNumber: phone,
            isDefault: true,
          ),
        );
      }
      _currentStep = 1;
    });
  }

  /// Saves user profile and all configured payment methods, then navigates home.
  Future<void> _saveAllAndStart() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final gcashItem = _paymentMethods
        .where((m) => m.provider.toLowerCase() == 'gcash')
        .firstOrNull;
    final mayaItem = _paymentMethods
        .where((m) => m.provider.toLowerCase() == 'maya')
        .firstOrNull;

    final result = await ref.read(currentUserProvider.notifier).completeProfile(
          displayName: name,
          phone: phone,
          avatarUrl: _selectedAvatar,
          gcashNumber: gcashItem?.accountNumber,
          mayaNumber: mayaItem?.accountNumber,
        );

    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _isSaving = false;
        _errorText = result.errorMessage ??
            'We could not save your profile. Please check your connection and try again.';
        if (result.isDuplicatePhone) {
          _currentStep = 0;
        }
      });
      return;
    }

    final userId = SupabaseConfig.currentUserId;
    if (userId != null && SupabaseConfig.isInitialized) {
      for (final item in _paymentMethods) {
        try {
          await SupabaseTabbyRepository.instance.createPaymentMethod(
            ownerUserId: userId,
            draft: item.toDraft(),
            makeDefault: item.isDefault,
          );
        } catch (e) {
          debugPrint('[CompleteProfileScreen] createPaymentMethod error: $e');
        }
      }
    }

    if (!mounted) return;

    AppState.profileCompletionRequired.value = false;
    context.go('/home');
  }

  /// Skips payment method configuration and immediately enters the app.
  Future<void> _skipAndStart() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final result = await ref.read(currentUserProvider.notifier).completeProfile(
          displayName: name,
          phone: phone,
          avatarUrl: _selectedAvatar,
        );

    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _isSaving = false;
        _errorText = result.errorMessage ??
            'We could not save your profile. Please check your connection and try again.';
        if (result.isDuplicatePhone) {
          _currentStep = 0;
        }
      });
      return;
    }

    AppState.profileCompletionRequired.value = false;
    context.go('/home');
  }

  /// Opens the dialog to add another payment rail.
  Future<void> _openAddPaymentDialog() async {
    final result = await showModalBottomSheet<_SetupPaymentItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddPaymentMethodSheet(
        defaultPhone: _phoneController.text.trim(),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result.isDefault) {
          for (final m in _paymentMethods) {
            m.isDefault = false;
          }
        }
        _paymentMethods.add(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TabbyColors.bgCanvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _currentStep == 0
                ? _buildStepOneIdentity()
                : _buildStepTwoPaymentRails(),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 1: SOCIAL IDENTITY
  // ---------------------------------------------------------------------------
  Widget _buildStepOneIdentity() {
    return Column(
      key: const ValueKey('step_1_identity'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        // Step progress pill
        _buildStepPill(
          step: 'Step 1 of 2',
          title: 'Social Identity',
        ),
        const SizedBox(height: 16),
        const Center(
          child: TabbyMascotWidget(
            emotion: MascotEmotion.idleNeutral,
            size: 78,
            showBubble: false,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Complete your profile',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: TabbyColors.brandDarkTeal,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your account is connected. Add your mobile number so friends can find you on Tabby.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: TabbyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        // Avatar Selection
        const Text(
          'CHOOSE PROFILE ICON',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: TabbyColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        _buildAvatarChoices(),
        const SizedBox(height: 20),
        // Full Name Field
        _buildField(
          controller: _nameController,
          label: 'Full name',
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        // Mobile Number Field
        _buildField(
          controller: _phoneController,
          label: 'Mobile number',
          hintText: '09XX-XXX-XXXX',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _goToStepTwo(),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorText!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TabbyColors.alertRed,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 24),
        TabbyButton(
          label: 'Save and continue',
          variant: TabbyButtonVariant.primary,
          isLoading: _isValidatingPhone,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          onPressed: _isValidatingPhone ? null : _goToStepTwo,
        ),
      ],
    );
  }

  Widget _buildAvatarChoices() {
    final options = [
      {'val': 'asset:mascot', 'label': 'Friendly', 'icon': Icons.pets_rounded},
      {'val': 'asset:cat_cool', 'label': 'Cool', 'icon': Icons.star_rounded},
      {'val': 'asset:camera_snap', 'label': 'Snap', 'icon': Icons.camera_alt_rounded},
      {'val': '', 'label': 'Initials', 'icon': Icons.account_circle_rounded},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: options.map((opt) {
        final isSelected = _selectedAvatar == opt['val'];
        return GestureDetector(
          onTap: () => setState(() => _selectedAvatar = opt['val'] as String),
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? TabbyColors.brandMintAccent
                  : TabbyColors.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? TabbyColors.brandEmerald
                    : TabbyColors.borderMint,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isSelected
                      ? TabbyColors.brandEmerald
                      : TabbyColors.iconBgMint,
                  child: Icon(
                    opt['icon'] as IconData,
                    size: 18,
                    color: isSelected
                        ? TabbyColors.surfaceWhite
                        : TabbyColors.brandDarkTeal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  opt['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: TabbyColors.brandDarkTeal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2: HOW FRIENDS PAY YOU (MULTI-PAYMENT METHOD MANAGER + AUTO-CROP)
  // ---------------------------------------------------------------------------
  Widget _buildStepTwoPaymentRails() {
    return Column(
      key: const ValueKey('step_2_payments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // Step progress pill with back action
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _currentStep = 0),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded,
                        size: 14, color: TabbyColors.brandDarkTeal),
                    SizedBox(width: 4),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TabbyColors.brandDarkTeal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildStepPill(
              step: 'Step 2 of 2',
              title: 'Payment Rails',
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Center(
          child: TabbyMascotWidget(
            emotion: MascotEmotion.calculating,
            size: 72,
            showBubble: false,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'How friends pay you',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: TabbyColors.brandDarkTeal,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Add your payment methods. When someone settles a tab, Tabby will show your details or auto-cropped QR instantly.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: TabbyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        // Payment methods card list
        if (_paymentMethods.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: TabbyColors.surfaceWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TabbyColors.borderMint),
            ),
            child: const Center(
              child: Text(
                'No payment methods added yet.\nTap below to add GCash, Maya, or Bank Transfer.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
              ),
            ),
          )
        else
          ..._paymentMethods.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return _buildPaymentMethodCard(item, idx);
          }),
        const SizedBox(height: 12),
        // Add another payment method button
        OutlinedButton.icon(
          onPressed: _openAddPaymentDialog,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('+ Add Another Payment Method'),
          style: OutlinedButton.styleFrom(
            foregroundColor: TabbyColors.brandDarkTeal,
            minimumSize: const Size(double.infinity, 48),
            side: const BorderSide(color: TabbyColors.borderMint, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorText!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TabbyColors.alertRed,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 20),
        TabbyButton(
          label: 'Complete Setup and Start',
          variant: TabbyButtonVariant.primary,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _saveAllAndStart,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _isSaving ? null : _skipAndStart,
          child: const Text(
            'Skip for now',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: TabbyColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(_SetupPaymentItem item, int index) {
    final isGcash = item.provider.toLowerCase() == 'gcash';
    final isMaya = item.provider.toLowerCase() == 'maya';
    final isBank = item.provider.toLowerCase() == 'bank_transfer';

    final Color badgeColor = isGcash
        ? TabbyColors.accentBlue
        : (isMaya ? TabbyColors.brandEmerald : TabbyColors.brandDarkTeal);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TabbyColors.surfaceWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: item.isDefault
              ? TabbyColors.brandEmerald
              : TabbyColors.borderMint,
          width: item.isDefault ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isBank
                      ? Icons.account_balance_rounded
                      : Icons.account_balance_wallet_rounded,
                  color: badgeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.displayName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                          ),
                        ),
                        if (item.isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: TabbyColors.brandMintAccent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Preferred',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.brandEmerald,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.accountNumber.isNotEmpty
                          ? item.accountNumber
                          : 'No number specified',
                      style: const TextStyle(
                        fontSize: 12,
                        color: TabbyColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: TabbyColors.alertRed, size: 20),
                tooltip: 'Remove',
                onPressed: () {
                  setState(() {
                    _paymentMethods.removeAt(index);
                    if (_paymentMethods.isNotEmpty &&
                        !_paymentMethods.any((m) => m.isDefault)) {
                      _paymentMethods.first.isDefault = true;
                    }
                  });
                },
              ),
            ],
          ),
          // QR Preview Thumbnail if attached
          if (item.qrBytes != null || item.generatedQrUrl != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TabbyColors.bgCanvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TabbyColors.borderMint),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.qrBytes != null
                        ? Image.memory(
                            item.qrBytes!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.contain,
                          )
                        : Image.network(
                            item.generatedQrUrl!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.contain,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              item.isAutoCropped
                                  ? Icons.crop_rounded
                                  : Icons.qr_code_2_rounded,
                              size: 14,
                              color: TabbyColors.brandEmerald,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.isAutoCropped
                                  ? 'Auto-cropped QR Code'
                                  : 'Attached QR Code',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: TabbyColors.brandEmerald,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Will be displayed when friends settle tabs.',
                          style: TextStyle(
                            fontSize: 10,
                            color: TabbyColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Preferred toggle row
          if (!item.isDefault) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    for (final m in _paymentMethods) {
                      m.isDefault = false;
                    }
                    item.isDefault = true;
                  });
                },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 14),
                label: const Text('Set as Preferred',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: TabbyColors.brandEmerald,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepPill({required String step, required String title}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: TabbyColors.brandMintAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$step: $title',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: TabbyColors.brandDarkTeal,
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: TabbyColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TabbyColors.borderMint),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: const TextStyle(
          color: TabbyColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          hintStyle: const TextStyle(color: TabbyColors.textMuted, fontSize: 13),
          labelStyle: const TextStyle(color: TabbyColors.textSecondary),
          prefixIcon: Icon(icon, color: TabbyColors.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MODAL SHEET: ADD PAYMENT METHOD + AUTO-CROP QR
// -----------------------------------------------------------------------------
class _AddPaymentMethodSheet extends StatefulWidget {
  const _AddPaymentMethodSheet({required this.defaultPhone});

  final String defaultPhone;

  @override
  State<_AddPaymentMethodSheet> createState() => _AddPaymentMethodSheetState();
}

class _AddPaymentMethodSheetState extends State<_AddPaymentMethodSheet> {
  String _provider = 'gcash';
  late final TextEditingController _nameController;
  final _accountController = TextEditingController();

  Uint8List? _qrBytes;
  String? _qrExtension;
  String? _qrMimeType;
  bool _isAutoCropped = false;
  bool _isCropping = false;

  String? _generatedQrUrl;
  bool _isGeneratingQr = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'GCash');
    if (widget.defaultPhone.isNotEmpty) {
      _accountController.text = widget.defaultPhone;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  Future<void> _pickAndCropQr() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() {
      _isCropping = true;
      _error = null;
    });

    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      setState(() {
        _isCropping = false;
        _error = 'QR image must be 10 MB or smaller.';
      });
      return;
    }

    final formatInfo = QrCodeCropper.detectImageFormat(
      name: file.name,
      path: file.path,
      mimeType: file.mimeType,
      bytes: bytes,
    );

    if (!formatInfo.isValid) {
      setState(() {
        _isCropping = false;
        _error = 'Use a JPG, PNG, WEBP, or HEIC image.';
      });
      return;
    }

    final extension = formatInfo.extension;

    // Run native automated QR detection & crop
    final cropResult = await QrCodeCropper.cropQrCode(bytes);
    final finalBytes = cropResult.wasCropped ? cropResult.bytes : bytes;
    final finalExtension = cropResult.wasCropped ? 'png' : extension;
    final finalMime = cropResult.wasCropped
        ? 'image/png'
        : (formatInfo.mimeType.isNotEmpty
            ? formatInfo.mimeType
            : (extension == 'jpg' || extension == 'jpeg'
                ? 'image/jpeg'
                : 'image/$extension'));

    setState(() {
      _qrBytes = finalBytes;
      _qrExtension = finalExtension;
      _qrMimeType = finalMime;
      _isAutoCropped = cropResult.wasCropped;
      _isCropping = false;
      _generatedQrUrl = null;
      _error = null;
    });
  }

  Future<void> _generateFromNumber() async {
    final account = _accountController.text.trim();
    if (account.isEmpty) {
      setState(() => _error = 'Enter an account number to generate a QR code.');
      return;
    }

    setState(() {
      _isGeneratingQr = true;
      _error = null;
      _qrBytes = null;
    });

    final url = TabbyApiServices.goQrUrl(account, size: 300);
    setState(() {
      _generatedQrUrl = url;
      _isGeneratingQr = false;
    });
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Add Payment Method',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: TabbyColors.brandDarkTeal,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Provider Chips
                const Text(
                  'PROVIDER',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: TabbyColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    _providerChip('gcash', 'GCash'),
                    _providerChip('maya', 'Maya'),
                    _providerChip('bank_transfer', 'Bank Transfer'),
                    _providerChip('cash', 'Cash'),
                    _providerChip('other', 'Other'),
                  ],
                ),
                const SizedBox(height: 14),
                // Name
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Payment method name',
                    hintText: 'e.g. GCash, Maya, BDO',
                  ),
                ),
                const SizedBox(height: 12),
                // Account number with quick-fill
                TextField(
                  controller: _accountController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Account number or mobile',
                    hintText: '09XX-XXX-XXXX',
                    suffixIcon: widget.defaultPhone.isNotEmpty &&
                            _accountController.text != widget.defaultPhone
                        ? TextButton(
                            onPressed: () {
                              setState(() {
                                _accountController.text = widget.defaultPhone;
                              });
                            },
                            child: const Text('Use phone',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: TabbyColors.brandEmerald)),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                // QR Code Upload & Crop
                const Text(
                  'PAYMENT QR CODE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: TabbyColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _isCropping ? null : _pickAndCropQr,
                  icon: _isCropping
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.crop_rounded, size: 18),
                  label: Text(_isCropping
                      ? 'Detecting & cropping QR...'
                      : (_qrBytes == null
                          ? 'Upload QR Screenshot (Auto-Crop)'
                          : 'Change QR Screenshot')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    foregroundColor: TabbyColors.brandDarkTeal,
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _isGeneratingQr ? null : _generateFromNumber,
                  icon: _isGeneratingQr
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Generate QR from Number'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    foregroundColor: TabbyColors.brandEmerald,
                    side: const BorderSide(color: TabbyColors.brandEmerald),
                  ),
                ),
                // Live preview of QR
                if (_qrBytes != null || _generatedQrUrl != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _qrBytes != null
                              ? Image.memory(
                                  _qrBytes!,
                                  width: 140,
                                  height: 140,
                                  fit: BoxFit.contain,
                                )
                              : Image.network(
                                  _generatedQrUrl!,
                                  width: 140,
                                  height: 140,
                                  fit: BoxFit.contain,
                                ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: TabbyColors.brandMintAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isAutoCropped
                                    ? Icons.crop_rounded
                                    : Icons.check_circle_rounded,
                                size: 13,
                                color: TabbyColors.brandEmerald,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isAutoCropped
                                    ? 'Auto-cropped from screenshot'
                                    : 'QR Code Ready',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal,
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
                  Text(_error!,
                      style: const TextStyle(
                          color: TabbyColors.alertRed, fontSize: 12)),
                ],
                const SizedBox(height: 18),
                TabbyButton(
                  label: 'Add Payment Method',
                  onPressed: () {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) {
                      setState(() => _error = 'Enter a payment method name.');
                      return;
                    }
                    Navigator.pop(
                      context,
                      _SetupPaymentItem(
                        provider: _provider,
                        displayName: name,
                        accountNumber: _accountController.text.trim(),
                        qrBytes: _qrBytes,
                        qrExtension: _qrExtension,
                        qrMimeType: _qrMimeType,
                        generatedQrUrl: _generatedQrUrl,
                        isAutoCropped: _isAutoCropped,
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

  Widget _providerChip(String key, String label) {
    final isSelected = _provider == key;
    return ChoiceChip(
      label: Text(label),
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
        if (val) {
          setState(() {
            _provider = key;
            if (key == 'gcash') _nameController.text = 'GCash';
            if (key == 'maya') _nameController.text = 'Maya';
            if (key == 'bank_transfer') _nameController.text = 'Bank Transfer';
            if (key == 'cash') _nameController.text = 'Cash';
          });
        }
      },
    );
  }
}
