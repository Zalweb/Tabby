import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/recovery_password_update.dart';
import '../../../core/services/auth_email_assistance.dart';
import '../../../core/services/auth_recovery_state.dart';
import '../../../shared/widgets/tabby_button.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.service});
  final RecoveryPasswordUpdate? service;
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;
  late final AuthRecoveryState _recovery;
  String? _scope;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _recovery = widget.service?.recovery ?? AuthRecoveryState.instance;
    _scope = '${_recovery.account}:${_recovery.sessionId}';
    _recovery.addListener(_scopeChanged);
  }

  void _scopeChanged() {
    final next = '${_recovery.account}:${_recovery.sessionId}';
    if (next == _scope) {
      if (mounted && _recovery.linkError != null) {
        setState(() => _error = _recovery.linkError);
      }
      return;
    }
    _scope = next;
    ++_generation;
    _password.clear();
    _confirmation.clear();
    if (mounted) {
      setState(() {
        _busy = false;
        _error =
            'Your account changed. Enter a password for this recovery session.';
      });
    }
  }

  @override
  void dispose() {
    _recovery.removeListener(_scopeChanged);
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.service ?? RecoveryPasswordUpdate.instance)
          .save(_password.text, _confirmation.text);
      if (!mounted || generation != _generation) return;
      _password.clear();
      _confirmation.clear();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error is AuthAssistanceException
            ? error.message
            : 'The password could not be updated. Request a new link if it has expired.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight),
          title: const Text('Reset password')),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Choose a new password for your Tabby account.'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration:
                            const InputDecoration(labelText: 'New password')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _confirmation,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Confirm new password')),
                    const SizedBox(height: 16),
                    if (_error != null) Text(_error!),
                    TabbyButton(
                        label: 'Save new password',
                        isLoading: _busy,
                        onPressed: _busy ? null : _save),
                    TextButton(
                        onPressed:
                            _busy ? null : () => context.go('/auth-help'),
                        child: const Text('Request a new recovery link')),
                  ]))));
}
