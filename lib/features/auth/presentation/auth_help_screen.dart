import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_state.dart';
import '../../../core/services/auth_email_assistance.dart';
import '../../../core/services/auth_recovery_state.dart';
import '../../../shared/widgets/tabby_button.dart';

class AuthHelpScreen extends StatefulWidget {
  const AuthHelpScreen(
      {super.key, this.assistance, this.initialKind = AuthEmailKind.recovery});
  final AuthEmailAssistance? assistance;
  final AuthEmailKind initialKind;
  @override
  State<AuthHelpScreen> createState() => _AuthHelpScreenState();
}

class _AuthHelpScreenState extends State<AuthHelpScreen> {
  final _email = TextEditingController();
  AuthEmailKind _kind = AuthEmailKind.recovery;
  bool _busy = false;
  int _remaining = 0;
  String? _message;
  Timer? _timer;
  AuthEmailAssistance get service =>
      widget.assistance ?? AuthEmailAssistance.instance;
  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _refreshCooldown();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshCooldown());
  }

  Future<void> _refreshCooldown() async {
    try {
      final value = await service.remainingSeconds();
      if (mounted && value != _remaining) setState(() => _remaining = value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await service.send(_kind, _email.text);
      if (mounted) {
        setState(() => _message =
            'If this address can receive a Tabby email, a link is on its way. Use the latest link you requested.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error is AuthAssistanceException
            ? error.message
            : 'The email request could not be accepted. Please try again later.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshCooldown();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: AuthRecoveryState.instance,
      builder: (context, _) => Scaffold(
            appBar: AppBar(
                toolbarHeight:
                    MediaQuery.textScalerOf(context).scale(kToolbarHeight),
                title: const Text('Account help'),
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      AuthRecoveryState.instance.clearLinkError();
                      context.go(
                          AppState.isAuthenticated.value ? '/home' : '/login');
                    })),
            body: SafeArea(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (AuthRecoveryState.instance.linkError != null)
                            Text(AuthRecoveryState.instance.linkError!),
                          const Text(
                              'Reset your password or request a new confirmation email.'),
                          const SizedBox(height: 16),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final kind in AuthEmailKind.values)
                              ChoiceChip(
                                  label: Text(kind == AuthEmailKind.recovery
                                      ? 'Reset password'
                                      : 'Confirm email'),
                                  selected: _kind == kind,
                                  onSelected: _busy
                                      ? null
                                      : (selected) {
                                          if (selected) {
                                            setState(() => _kind = kind);
                                          }
                                        }),
                          ]),
                          const SizedBox(height: 16),
                          TextField(
                              controller: _email,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration:
                                  const InputDecoration(labelText: 'Email')),
                          const SizedBox(height: 16),
                          if (_message != null) Text(_message!),
                          const SizedBox(height: 16),
                          TabbyButton(
                              label: _remaining > 0
                                  ? 'Try again in $_remaining seconds'
                                  : 'Send email',
                              isLoading: _busy,
                              onPressed:
                                  _busy || _remaining > 0 ? null : _send),
                          const SizedBox(height: 12),
                          const Text(
                              'Email delivery can take a few minutes. Check your spam folder. Request and open a recovery link on the same device.'),
                        ]))),
          ));
}
