import '../../../shared/widgets/tabby_feedback.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/tabby_button.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/form_draft_store.dart';
import '../../../core/theme/motion_preferences.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart';
import '../../payment_methods/presentation/payment_methods_sheet.dart';
import '../application/profile_email_change.dart';

class ProfileEditSheet extends ConsumerStatefulWidget {
  const ProfileEditSheet({
    super.key,
    required this.user,
    this.save,
    this.changeEmail,
  });
  final TabbyUser user;
  final Future<ProfileUpdateResult> Function(String name, String? phone)? save;
  final Future<void> Function(String email)? changeEmail;

  @override
  ConsumerState<ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<ProfileEditSheet> {
  late final _name = TextEditingController(text: widget.user.displayName);
  late final _phone = TextEditingController(text: widget.user.phone);
  final _email = TextEditingController();
  bool _saving = false, _emailPending = false;
  bool _leaving = false;
  String? _error, _emailStatus;
  final _store = const FormDraftStore();
  bool _draftReady = false, _restoring = false, _prompting = false;
  bool get _busy => _saving || _emailPending || !_draftReady;
  Map<String, dynamic> _snapshot() => {
    'name': _name.text,
    'phone': _phone.text,
    'email': _email.text,
    'base_name': widget.user.displayName,
    'base_phone': widget.user.phone,
  };
  bool get _dirty =>
      _name.text != widget.user.displayName ||
      _phone.text != widget.user.phone ||
      _email.text.isNotEmpty;
  Future<void> _persist() async {
    if (_draftReady && !_restoring && _current && !_leaving) {
      await _store.write(widget.user.id, 'profile-edit', _snapshot());
    }
  }

  void _edited() {
    if (!_draftReady || _restoring || !_current) return;
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

  Future<void> _restore() async {
    try {
      final map = await _store.read(widget.user.id, 'profile-edit');
      if (!_current) return;
      if (map != null) {
        if (map['base_name'] != widget.user.displayName ||
            map['base_phone'] != widget.user.phone) {
          throw StateError('Profile changed since draft');
        }
        _restoring = true;
        _name.text = map['name'] as String;
        _phone.text = map['phone'] as String;
        _email.text = map['email'] as String;
      }
      _restoring = false;
      setState(() => _draftReady = true);
    } catch (_) {
      _restoring = false;
      if (_current) {
        setState(
          () => _error = 'Your profile draft could not be restored. Retry or discard it before editing.',
        );
      }
    }
  }

  Future<void> _close() async {
    if (_saving || _emailPending || _prompting || !_current) return;
    _prompting = true;
    try {
      final choice = await showDialog<String>(
        context: context,
        animationStyle: TabbyMotion.style(context),
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('Keep your profile edits?'),
          content: const Text(
            'Keep a private draft to finish later, or discard these unsaved edits.',
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
              onPressed: _draftReady
                  ? () => Navigator.pop(dialog, 'keep')
                  : null,
              child: const Text('Keep draft'),
            ),
          ],
        ),
      );
      if (choice == null || !_current) return;
      if (choice == 'keep') {
        await _persist();
      } else {
        await _store.remove(widget.user.id, 'profile-edit');
      }
      if (!mounted || !_current) return;
      _leaving = true;
      Navigator.pop(context);
    } catch (_) {
      if (_current) {
        setState(() => _error = 'Draft could not be saved. Please retry.');
      }
    } finally {
      _prompting = false;
    }
  }

  bool get _current =>
      mounted && ref.read(currentUserProvider).id == widget.user.id;

  @override
  void initState() {
    super.initState();
    SupabaseConfig.sessionRevision.addListener(_sessionChanged);
    for (final controller in [_name, _phone, _email]) {
      controller.addListener(_edited);
    }
    _restore();
  }

  void _sessionChanged() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null) return;
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    SupabaseConfig.sessionRevision.removeListener(_sessionChanged);
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_current) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _name.text.trim(), phone = _phone.text.trim();
    ProfileUpdateResult result;
    try {
      await _persist();
      if (!_current) return;
      result =
          await (widget.save?.call(
                name,
                phone == widget.user.phone ? null : phone,
              ) ??
              ref
                  .read(currentUserProvider.notifier)
                  .updateProfile(
                    displayName: name,
                    phone: phone == widget.user.phone ? null : phone,
                  ));
    } catch (_) {
      result = ProfileUpdateResult.failure;
    }
    if (!mounted || !_current) return;
    setState(() {
      _saving = false;
      _error = result.isSuccess ? null : result.errorMessage ?? 'Profile could not be saved. Your edits are still here. Please retry.';
    });
    if (result.isSuccess) {
      final messenger = TabbyFeedback.of(context);
      try {
        await _store.remove(widget.user.id, 'profile-edit');
      } catch (_) {}
      if (!mounted || !_current) return;
      _leaving = true;
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Profile saved.')));
    }
  }

  Future<void> _requestEmail() async {
    if (_busy || !_current) return;
    final email = _email.text.trim();
    if (email.toLowerCase() ==
        ref.read(currentUserProvider).email.toLowerCase()) {
      setState(() => _emailStatus = 'Enter a different email address.');
      return;
    }
    setState(() {
      _emailPending = true;
      _emailStatus = null;
    });
    try {
      await (widget.changeEmail?.call(email) ??
          ProfileEmailChange.instance.send(email));
      if (_current) {
        setState(
          () => _emailStatus = 'Verification requested. Follow the instructions sent to your email addresses. Your current email stays in use until Auth confirms the change.',
        );
      }
    } catch (_) {
      if (_current) {
        setState(
          () => _emailStatus = 'Email change could not be requested. Check the address and connection, then retry.',
        );
      }
    } finally {
      if (_current) setState(() => _emailPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (previous, next) {
      if (next.id != widget.user.id) {
        _sessionChanged();
      }
    });
    final user = ref.watch(currentUserProvider);
    return PopScope(
      canPop: _leaving || (!_busy && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Material(
        borderRadius: isTabbyFormPage(context)
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              MediaQuery.viewInsetsOf(context).bottom + 20,
            ),
            child: TabbyFormBody(
              header: TabbyFormHeader(
                title: 'Edit Profile',
                onBack: _busy ? null : () => Navigator.maybePop(context),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                    ),
                  ),
                  TextField(
                    controller: _phone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_error!, semanticsLabel: _error),
                    ),
                  if (!_draftReady)
                    TextButton(
                      onPressed: _restore,
                      child: const Text('Retry draft'),
                    ),
                  const SizedBox(height: 16),
                  TabbyButton(
                    label: 'Save profile',
                    isLoading: _saving,
                    onPressed: _busy ? null : _save,
                  ),
                  const Divider(height: 32),
                  Text('Current email: ${user.email}'),
                  const Text(
                    'Email changes require verification and are separate from saving your profile.',
                  ),
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() => _emailStatus = null),
                    decoration: const InputDecoration(
                      labelText: 'New email address',
                    ),
                  ),
                  if (_emailStatus != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_emailStatus!),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _requestEmail,
                    child: Text(
                      _emailPending
                          ? 'Requesting verification…'
                          : 'Request email change',
                    ),
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Receiving details are managed with your saved payment methods.',
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => PaymentMethodsSheet.show(
                            context,
                            ownerUserId: user.id,
                          ),
                    child: const Text('Manage payment methods'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
