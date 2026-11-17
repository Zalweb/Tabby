import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/profile/application/profile_email_change.dart';
import 'package:tabby/features/profile/presentation/profile_edit_sheet.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const fixture = TabbyUser(
    id: 'fixture-owner',
    displayName: 'Original name',
    phone: '+639171234567',
    email: 'old@example.invalid');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('waits for acknowledged row and uses canonical server values', () async {
    final response = Completer<ProfileUpdateResult>();
    Map<String, String>? sent;
    final profile = CurrentUserNotifier(
        initialUser: fixture,
        autoLoad: false,
        saveProfile: (changes) {
          sent = changes;
          return response.future;
        });
    addTearDown(profile.dispose);
    final saving =
        profile.updateProfile(displayName: ' Edited ', phone: '09181234567');
    expect(profile.state.displayName, fixture.displayName);
    expect(sent, {'display_name': 'Edited', 'phone': '+639181234567'});
    response.complete(ProfileUpdateResult(
        isSuccess: true,
        user: fixture.copyWith(
            displayName: 'Server accepted', phone: '+639181234567')));
    expect((await saving).isSuccess, isTrue);
    expect(profile.state.displayName, 'Server accepted');
    expect(profile.state.email, fixture.email);
  });
  test('rejection and thrown transport error preserve previous profile',
      () async {
    var throws = false;
    final profile = CurrentUserNotifier(
        initialUser: fixture,
        autoLoad: false,
        saveProfile: (_) async {
          if (throws) throw StateError('offline');
          return const ProfileUpdateResult(
              isSuccess: false, isDuplicatePhone: true);
        });
    addTearDown(profile.dispose);
    expect(
        (await profile.updateProfile(displayName: 'Rejected')).isDuplicatePhone,
        isTrue);
    expect(profile.state, same(fixture));
    throws = true;
    expect(
        (await profile.updateProfile(displayName: 'Retry')).isSuccess, isFalse);
    expect(profile.state, same(fixture));
  });
  test('late result after same-account new session or disposal is discarded',
      () async {
    var generation = 1;
    final response = Completer<ProfileUpdateResult>();
    final profile = CurrentUserNotifier(
        initialUser: fixture,
        autoLoad: false,
        captureCurrent: () {
          final captured = generation;
          return () => captured == generation;
        },
        saveProfile: (_) => response.future);
    final saving = profile.updateProfile(displayName: 'Late');
    generation++;
    response.complete(ProfileUpdateResult.success);
    expect((await saving).isSuccess, isFalse);
    expect(profile.state, same(fixture));
    profile.dispose();
    final another = Completer<ProfileUpdateResult>();
    final disposed = CurrentUserNotifier(
        initialUser: fixture,
        autoLoad: false,
        saveProfile: (_) => another.future);
    final pending = disposed.updateProfile(displayName: 'Disposed');
    disposed.dispose();
    another.complete(ProfileUpdateResult.success);
    expect((await pending).isSuccess, isFalse);
  });
  test('parallel saves cannot overwrite a pending command', () async {
    var calls = 0;
    final response = Completer<ProfileUpdateResult>();
    final profile = CurrentUserNotifier(
        initialUser: fixture,
        autoLoad: false,
        saveProfile: (_) {
          calls++;
          return response.future;
        });
    addTearDown(profile.dispose);
    final first = profile.updateProfile(displayName: 'First');
    expect((await profile.updateProfile(displayName: 'Second')).isSuccess,
        isFalse);
    expect(calls, 1);
    response.complete(ProfileUpdateResult.success);
    await first;
    expect(profile.state.displayName, 'First');
  });
  test('invalid inputs and foreign response never change state', () async {
    var calls = 0;
    final profile = CurrentUserNotifier(
        initialUser: fixture,
        autoLoad: false,
        saveProfile: (_) async {
          calls++;
          return const ProfileUpdateResult(
              isSuccess: true,
              user: TabbyUser(
                  id: 'another', displayName: 'Other', email: '', phone: ''));
        });
    addTearDown(profile.dispose);
    expect((await profile.updateProfile(phone: '123')).isSuccess, isFalse);
    expect((await profile.updateProfile(displayName: '  ')).isSuccess, isFalse);
    expect(calls, 0);
    expect(
        (await profile.updateProfile(displayName: 'Valid')).isSuccess, isFalse);
    expect(profile.state, same(fixture));
  });
  test('email request waits, suppresses concurrent sends and persists cooldown',
      () async {
    var calls = 0;
    final ack = Completer<void>();
    final service = ProfileEmailChange(
        account: () => fixture.id,
        captureCurrent: () => () => true,
        request: (email) {
          calls++;
          expect(email, 'new@example.invalid');
          return ack.future;
        });
    final sending = service.send(' new@example.invalid ');
    await expectLater(service.send('other@example.invalid'), throwsException);
    await Future<void>.delayed(Duration.zero);
    ack.complete();
    await sending;
    expect(calls, 1);
    final restarted = ProfileEmailChange(
        account: () => fixture.id,
        captureCurrent: () => () => true,
        request: (_) async {
          calls++;
        });
    await expectLater(restarted.send('new@example.invalid'), throwsException);
    expect(calls, 1);
  });
  test('email failure and late session response never acknowledge success',
      () async {
    var valid = true;
    final ack = Completer<void>();
    final service = ProfileEmailChange(
        account: () => fixture.id,
        captureCurrent: () => () => valid,
        request: (_) => ack.future);
    final pending = service.send('new@example.invalid');
    await Future<void>.delayed(Duration.zero);
    valid = false;
    ack.complete();
    await expectLater(pending, throwsException);
    FlutterSecureStorage.setMockInitialValues({});
    final failure = ProfileEmailChange(
        account: () => fixture.id,
        captureCurrent: () => () => true,
        request: (_) async => throw StateError('transport'));
    await expectLater(failure.send('new@example.invalid'), throwsStateError);
  });

  Future<void> open(WidgetTester tester, ProfileEditSheet sheet) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((_) =>
              CurrentUserNotifier(initialUser: fixture, autoLoad: false)),
        ],
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => sheet),
                        child: const Text('Open profile')))))));
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'failed profile save keeps edits open and removes duplicate wallet fields',
      (tester) async {
    final ack = Completer<ProfileUpdateResult>();
    await open(tester,
        ProfileEditSheet(user: fixture, save: (name, phone) => ack.future));
    expect(find.text('GCash Number'), findsNothing);
    expect(find.text('Maya Number'), findsNothing);
    expect(find.text('Manage payment methods'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Display name'), 'Retained draft');
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Display name'))
            .enabled,
        isFalse);
    expect(find.byType(ProfileEditSheet), findsOneWidget);
    ack.complete(const ProfileUpdateResult(
        isSuccess: false, errorMessage: 'Synthetic rejection'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic rejection'), findsOneWidget);
    expect(find.text('Retained draft'), findsOneWidget);
    expect(find.text('Profile saved.'), findsNothing);
  });
  testWidgets('profile success closes only after acknowledgment',
      (tester) async {
    final ack = Completer<ProfileUpdateResult>();
    await open(tester,
        ProfileEditSheet(user: fixture, save: (name, phone) => ack.future));
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    expect(find.byType(ProfileEditSheet), findsOneWidget);
    ack.complete(ProfileUpdateResult.success);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditSheet), findsNothing);
    expect(find.text('Profile saved.'), findsOneWidget);
  });
  testWidgets(
      'account and session changes close one sheet without popping home',
      (tester) async {
    final ack = Completer<ProfileUpdateResult>();
    await open(tester,
        ProfileEditSheet(user: fixture, save: (name, phone) => ack.future));
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    final context = tester.element(find.byType(ProfileEditSheet));
    final container = ProviderScope.containerOf(context);
    container.read(currentUserProvider.notifier).state = const TabbyUser(
        id: 'new-actor', displayName: 'New actor', email: '', phone: '');
    SupabaseConfig.sessionRevision.value++;
    await tester.pumpAndSettle();
    ack.complete(ProfileUpdateResult.success);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditSheet), findsNothing);
    expect(find.text('Open profile'), findsOneWidget);
    expect(Navigator.of(tester.element(find.text('Open profile'))).canPop(),
        isFalse);
    expect(find.text('Profile saved.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('email request keeps current email and form until verification',
      (tester) async {
    final ack = Completer<void>();
    await open(tester,
        ProfileEditSheet(user: fixture, changeEmail: (_) => ack.future));
    await tester.enterText(find.widgetWithText(TextField, 'New email address'),
        'new@example.invalid');
    await tester.ensureVisible(find.text('Request email change'));
    await tester.tap(find.text('Request email change'));
    await tester.pump();
    expect(find.text('Requesting verification…'), findsOneWidget);
    expect(find.textContaining('Verification requested.'), findsNothing);
    ack.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Verification requested.'), findsOneWidget);
    expect(find.text('Current email: old@example.invalid'), findsOneWidget);
    expect(find.byType(ProfileEditSheet), findsOneWidget);
  });
}
