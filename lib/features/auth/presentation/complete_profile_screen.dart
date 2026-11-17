import '../../../shared/widgets/tabby_feedback.dart';
import 'auth_welcome_widgets.dart';
import '../../../core/theme/motion_preferences.dart';
import '../../../core/utils/philippine_phone.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../application/profile_setup_draft.dart';
import '../../payment_methods/presentation/payment_methods_sheet.dart';
import '../../payment_methods/domain/payment_method.dart' as receiving;
import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key, this.saveMethod});
  final Future<receiving.PaymentMethod?> Function(
    receiving.PaymentMethodDraft,
    bool,
  )?
  saveMethod;

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
  late final ProfileSetupDraft _setup;
  List<SetupPaymentItem> get _paymentMethods => _setup.items;
  bool _restoring = true, _restoreFailed = false;
  late final bool Function() _currentSession;

  bool _isSaving = false;
  bool _isValidatingPhone = false;
  String? _errorText;
  String _baselineName = '',
      _baselinePhone = '',
      _baselineAvatar = 'asset:mascot';
  bool _allowExit = false, _handlingBack = false;
  bool get _identityDirty =>
      _nameController.text.trim() != _baselineName ||
      _phoneController.text.trim() != _baselinePhone ||
      _selectedAvatar != _baselineAvatar;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    final stamp = SupabaseConfig.captureSession();
    _currentSession = () => mounted && SupabaseConfig.isCurrentSession(stamp);
    _setup = ProfileSetupDraft(SupabaseConfig.currentUserId ?? user.id);
    _setup.addListener(_setupChanged);
    unawaited(_restoreSetup());
    final ownProfile =
        !SupabaseConfig.isInitialized ||
        user.id == SupabaseConfig.currentUserId;
    _nameController = TextEditingController(
      text: ownProfile ? user.displayName : '',
    );
    _phoneController.text = ownProfile ? user.phone : '';
    if (ownProfile && user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
      _selectedAvatar = user.avatarUrl!;
    }
    _rememberIdentity();
  }

  @override
  void dispose() {
    _setup.removeListener(_setupChanged);
    _setup.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _setupChanged() {
    if (_currentSession()) setState(() {});
  }

  Future<void> _restoreSetup() async {
    try {
      final restored = await _setup.restore();
      if (!_currentSession()) return;
      if (restored) {
        _nameController.text = _setup.name;
        _phoneController.text = _setup.phone;
        _selectedAvatar = _setup.avatar;
        _currentStep = _setup.step.clamp(0, 1);
        _rememberIdentity();
      }
      setState(() {
        _restoring = false;
        _restoreFailed = false;
      });
    } catch (_) {
      if (_currentSession()) {
        setState(() {
          _restoring = false;
          _restoreFailed = true;
        });
      }
    }
  }

  Future<void> _persistSetup() async {
    if (!_currentSession()) throw StateError('Account changed');
    _setup.name = _nameController.text.trim();
    _setup.phone = _phoneController.text.trim();
    _setup.avatar = _selectedAvatar;
    _setup.step = _currentStep;
    await _setup.persist();
    if (_currentSession()) setState(_rememberIdentity);
  }

  void _rememberIdentity() {
    _baselineName = _nameController.text.trim();
    _baselinePhone = _phoneController.text.trim();
    _baselineAvatar = _selectedAvatar;
  }

  Future<void> _backStep() async {
    if (_isSaving || _isValidatingPhone || !_currentSession()) return;
    setState(() => _currentStep = 0);
    try {
      await _persistSetup();
    } catch (_) {
      if (_currentSession()) {
        setState(
          () => _errorText = 'Your draft could not be saved. Please try again.',
        );
      }
    }
  }

  Future<void> _back() async {
    if (_handlingBack || _isSaving || _isValidatingPhone) return;
    if (_currentStep > 0) {
      await _backStep();
      return;
    }
    if (!_identityDirty) return;
    _handlingBack = true;
    try {
      final leave = await showDialog<bool>(
        animationStyle: TabbyMotion.style(context),
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('Keep your setup draft?'),
          content: const Text(
            'Save your edits on this device before leaving, or keep editing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Save draft and go back'),
            ),
          ],
        ),
      );
      if (leave != true || !_currentSession()) return;
      await _persistSetup();
      if (!_currentSession()) return;
      setState(() => _allowExit = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (!await Navigator.of(context).maybePop()) await SystemNavigator.pop();
    } catch (_) {
      if (_currentSession()) {
        setState(
          () => _errorText = 'Your draft could not be saved. Please try again.',
        );
      }
    } finally {
      _handlingBack = false;
    }
  }

  /// Validates Step 1 and advances to Step 2
  Future<void> _goToStepTwo() async {
    final name = _nameController.text.trim();
    final phone =
        normalizePhilippineMobile(_phoneController.text) ??
        _phoneController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorText = 'Please enter your full name.');
      return;
    }
    if (normalizePhilippineMobile(phone) == null) {
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
          _errorText = 'This mobile number is already linked to another Tabby account. Please enter a different number.';
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
      _phoneController.text = phone;
      _currentStep = 1;
    });
    try {
      await _persistSetup();
    } catch (_) {
      if (_currentSession()) {
        setState(
          () => _errorText =
              "Your setup draft could not be saved. Please try again.",
        );
      }
    }
  }

  Future<void> _saveAllAndStart() => _finishSetup(skip: false);
  Future<void> _skipAndStart() => _finishSetup(skip: true);
  Future<void> _finishSetup({required bool skip}) async {
    if (_isSaving || !_currentSession()) return;
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await _persistSetup();
      if (!_currentSession()) return;
      final result = await ref
          .read(currentUserProvider.notifier)
          .completeProfile(
            displayName: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            avatarUrl: _selectedAvatar,
          );
      if (!_currentSession()) return;
      if (!result.isSuccess) {
        setState(() {
          _errorText =
              result.errorMessage ??
              'Your profile could not be saved. Please try again.';
          if (result.isDuplicatePhone) _currentStep = 0;
        });
        return;
      }
      if (!skip) {
        final saved = await _setup.saveMethods(
          widget.saveMethod ??
              (draft, preferred) =>
                  SupabaseTabbyRepository.instance.createPaymentMethod(
                    ownerUserId: _setup.owner,
                    draft: draft,
                    makeDefault: preferred,
                  ),
          current: _currentSession,
        );
        if (!_currentSession()) return;
        if (!saved) {
          setState(
            () => _errorText = 'Some receiving methods are still waiting to save. Retry the unsaved methods or continue without them.',
          );
          return;
        }
      }
      if (skip && _paymentMethods.any((item) => !item.saved)) {
        await _setup.defer();
      } else {
        await _setup.clear();
      }
      if (!mounted || !_currentSession()) return;
      AppState.profileCompletionRequired.value = false;
      context.go('/home');
    } catch (_) {
      if (_currentSession()) {
        setState(
          () => _errorText =
              'Your setup could not be saved. Your draft is kept for retry.',
        );
      }
    } finally {
      if (_currentSession()) setState(() => _isSaving = false);
    }
  }

  /// Opens the dialog to add another payment rail.
  Future<void> _openAddPaymentDialog() async {
    if (_isSaving) return;
    await showTabbyFormPage<void>(
      context: context,
      builder: (_) => ReceivingMethodEditor(
        ownerId: _setup.owner,
        staged: true,
        onSave: (draft) async {
          if (!_currentSession()) return false;
          await _persistSetup();
          if (!_currentSession()) return false;
          await _setup.add(draft);
          return _currentSession();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring || _restoreFailed) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: _restoring
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Your setup draft could not be restored.'),
                      TextButton(
                        onPressed: () {
                          setState(() => _restoring = true);
                          _restoreSetup();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }
    return PopScope<Object?>(
      canPop:
          !_isSaving &&
          !_isValidatingPhone &&
          _currentStep == 0 &&
          (!_identityDirty || _allowExit),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: WelcomeColors.canvas(context),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AnimatedSwitcher(
                  duration: TabbyMotion.duration(
                    context,
                    const Duration(milliseconds: 250),
                  ),
                  child: _currentStep == 0
                      ? _buildStepOneIdentity()
                      : _buildStepTwoPaymentRails(),
                ),
              ),
            ),
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
        _buildStepPill(step: 'Step 1 of 2', title: 'Your details'),
        const SizedBox(height: 16),
        const Center(
          child: WelcomeMascot(
            asset: 'assets/branding/tabby-notebook-v3.png',
            size: 190,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Complete your profile',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: TabbyPalette.of(context).text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'What should friends call you? Add your mobile number so they can find the right you.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: TabbyPalette.of(context).secondaryText,
          ),
        ),
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
            style: TextStyle(
              color: TabbyPalette.of(context).errorText,
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
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _isSaving ? null : _backStep,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 14,
                      color: TabbyPalette.of(context).text,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TabbyPalette.of(context).text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildStepPill(step: 'Step 2 of 2', title: 'Receiving details'),
          ],
        ),
        const SizedBox(height: 14),
        const Center(
          child: WelcomeMascot(
            asset: 'assets/branding/tabby-notebook-v3.png',
            size: 190,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'How friends pay you',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: TabbyPalette.of(context).text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Add receiving details you choose to share. Upload QR images exported by your wallet or bank.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: TabbyPalette.of(context).secondaryText,
          ),
        ),
        const SizedBox(height: 20),
        // Payment methods card list
        if (_paymentMethods.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: TabbyPalette.of(context).surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TabbyPalette.of(context).border),
            ),
            child: Center(
              child: Text(
                'No payment methods added yet.\nTap below to add GCash, Maya, or Bank Transfer.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: TabbyPalette.of(context).secondaryText,
                ),
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
          onPressed: _isSaving ? null : _openAddPaymentDialog,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('+ Add Another Payment Method'),
          style: OutlinedButton.styleFrom(
            foregroundColor: TabbyPalette.of(context).text,
            minimumSize: const Size(double.infinity, 48),
            side: BorderSide(
              color: TabbyPalette.of(context).border,
              width: 1.5,
            ),
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
            style: TextStyle(
              color: TabbyPalette.of(context).errorText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 20),
        TabbyButton(
          label: _paymentMethods.any((item) => item.attempted && !item.saved)
              ? 'Retry Unsaved Methods'
              : 'Complete Setup and Start',
          variant: TabbyButtonVariant.primary,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _saveAllAndStart,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _isSaving ? null : _skipAndStart,
          child: Text(
            _paymentMethods.any((item) => !item.saved)
                ? 'Continue without unsaved methods'
                : 'Skip for now',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: TabbyPalette.of(context).secondaryText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(SetupPaymentItem item, int index) {
    final isBank = item.provider.toLowerCase() == 'bank_transfer';

    final Color badgeColor = TabbyPalette.of(context).link;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: item.isDefault
              ? TabbyColors.brandAmber
              : TabbyPalette.of(context).border,
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          item.displayName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        if (item.isDefault) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: TabbyPalette.of(context).soft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Preferred',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: TabbyPalette.of(context).link,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: TabbyPalette.of(context).secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: TabbyPalette.of(context).errorText,
                  size: 20,
                ),
                tooltip: 'Remove',
                onPressed: _isSaving || item.attempted
                    ? null
                    : () async {
                        try {
                          await _setup.remove(index);
                        } catch (_) {
                          if (_currentSession()) {
                            setState(
                              () => _errorText = 'The draft could not be changed. Please try again.',
                            );
                          }
                        }
                      },
              ),
            ],
          ),
          Text(
            item.saved
                ? 'Saved'
                : (item.error ??
                      (item.attempted
                          ? 'Waiting for acknowledgment'
                          : 'Ready to save')),
          ),
          // QR Preview Thumbnail if attached
          if (item.qrBytes != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TabbyPalette.of(context).canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TabbyPalette.of(context).border),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      item.qrBytes!,
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
                              color: TabbyPalette.of(context).link,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                item.isAutoCropped
                                    ? 'Auto-cropped QR Code'
                                    : 'Attached QR Code',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyPalette.of(context).link,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Will be displayed when friends settle tabs.',
                          style: TextStyle(
                            fontSize: 10,
                            color: TabbyPalette.of(context).secondaryText,
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
                onPressed: _isSaving || _setup.hasAttempts
                    ? null
                    : () async {
                        try {
                          await _setup.prefer(item);
                        } catch (_) {
                          if (_currentSession()) {
                            setState(
                              () => _errorText = 'The preference could not be saved. Please try again.',
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 14),
                label: const Text(
                  'Set as Preferred',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: TabbyPalette.of(context).link,
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
        color: TabbyPalette.of(context).soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$step: $title',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: TabbyPalette.of(context).text,
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
        color: TabbyPalette.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TabbyPalette.of(context).border),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() => _allowExit = false),
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: TextStyle(
          color: TabbyPalette.of(context).text,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          hintStyle: TextStyle(
            color: TabbyPalette.of(context).mutedText,
            fontSize: 13,
          ),
          labelStyle: TextStyle(color: TabbyPalette.of(context).secondaryText),

          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
