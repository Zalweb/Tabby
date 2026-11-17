import 'package:flutter/material.dart';

import '../../../core/config/app_state.dart';
import '../application/registration_flow.dart';
import 'auth_welcome_widgets.dart';

class RegistrationCheckScreen extends StatelessWidget {
  const RegistrationCheckScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WelcomeColors.canvas(context),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ValueListenableBuilder<String?>(
              valueListenable: AppState.registrationError,
              builder: (context, error, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WelcomeMascot(size: 200),
                  Text(
                    error ?? 'Getting your tabs ready…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: WelcomeColors.ink(context),
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (error == null)
                    const CircularProgressIndicator()
                  else
                    FilledButton(
                      onPressed: () =>
                          RegistrationFlow.refresh().catchError((Object _) {}),
                      child: const Text('Try again'),
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
