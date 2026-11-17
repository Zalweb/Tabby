import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/onboarding/presentation/onboarding_screen.dart';
import 'package:tabby/features/auth/presentation/login_screen.dart';
import 'package:tabby/features/auth/presentation/signup_screen.dart';
import 'package:tabby/features/auth/presentation/auth_help_screen.dart';
import 'package:tabby/features/auth/presentation/reset_password_screen.dart';
import 'package:tabby/features/auth/presentation/complete_profile_screen.dart';
import 'package:tabby/features/auth/application/profile_setup_draft.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';
import 'package:tabby/features/payment_methods/presentation/payment_methods_sheet.dart';

Widget host(Widget child, {double scale = 1}) => ProviderScope(
    child: MaterialApp(
        builder: (context, content) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: content!),
        home: child));
Future<void> viewport(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(320, 480)
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'onboarding at $size / ${scale}x has reachable controls and back steps',
          (tester) async {
        await viewport(tester, size);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(host(const OnboardingScreen(), scale: scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 1; i <= 2; i++) {
          await tester.ensureVisible(find.text('Next'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(find.bySemanticsLabel('Step ${i + 1} of 3'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);
        expect(
            tester
                .widget<PopScope<Object?>>(find.byType(PopScope<Object?>))
                .canPop,
            isTrue);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      });
    }
  }
  for (final entry in <String, Widget>{
    'login': const LoginScreen(),
    'signup': const SignUpScreen(),
    'help': const AuthHelpScreen(),
    'reset': const ResetPasswordScreen()
  }.entries) {
    testWidgets(
        '${entry.key} at 200 percent small landscape remains scrollable',
        (tester) async {
      await viewport(tester, const Size(568, 320));
      await tester.pumpWidget(host(entry.value, scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
      'setup back returns one step and pristine identity does not prompt',
      (tester) async {
    final platformCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final setup = ProfileSetupDraft('user-me')
      ..name = 'Synthetic setup'
      ..phone = '+639171234567'
      ..step = 1;
    await setup.persist();
    await tester.pumpWidget(host(const CompleteProfileScreen()));
    await tester.pumpAndSettle();
    expect(find.text('How friends pay you'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isTrue);
    await tester.enterText(
        find.widgetWithText(TextField, 'Full name'), 'Unsaved synthetic edit');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Keep your setup draft?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved synthetic edit'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save draft and go back'));
    await tester.pumpAndSettle();
    final retained = ProfileSetupDraft('user-me');
    await retained.restore();
    expect(retained.name, 'Unsaved synthetic edit');
    expect(platformCalls, contains('SystemNavigator.pop'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'signup asks before losing edits and leaves pristine state unblocked',
      (tester) async {
    await viewport(tester, const Size(320, 568));
    await tester.pumpWidget(host(const SignUpScreen(), scale: 2));
    await tester.pumpAndSettle();
    expect(
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
        isTrue);
    await tester.enterText(
        find.widgetWithText(TextField, 'Full name'), 'Synthetic registration');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Leave account setup?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic registration'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'setup QR/details at 200 percent small width fit and can reach the completion action',
      (tester) async {
    await viewport(tester, const Size(320, 568));
    final setup = ProfileSetupDraft('user-me')
      ..name = 'Synthetic setup'
      ..phone = '+639171234567'
      ..step = 1;
    // Decoded synthetic PNG for layout only, not a wallet-validation/device test.
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==');
    await setup.add(PaymentMethodDraft(
        provider: 'gcash',
        displayName: 'A longer synthetic receiving method',
        accountLabel: 'Synthetic manual receiving details',
        qrBytes: bytes));
    await tester.pumpWidget(host(const CompleteProfileScreen(), scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Complete Setup and Start'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Complete your profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'staged receiving editor prompts only for unsaved edits and adapts large text',
      (tester) async {
    await viewport(tester, const Size(320, 568));
    await tester.pumpWidget(host(
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ReceivingMethodEditor(
                            staged: true, onSave: (_) async => true)),
                    child: const Text('Open setup editor')))),
        scale: 2));
    await tester.tap(find.text('Open setup editor'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ReceivingMethodEditor), findsNothing);
    await tester.tap(find.text('Open setup editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Payment method name'),
        'Synthetic draft');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Keep this receiving-method draft?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceivingMethodEditor), findsOneWidget);
    await tester.ensureVisible(find.text('These are my receiving details'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceivingMethodEditor), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
