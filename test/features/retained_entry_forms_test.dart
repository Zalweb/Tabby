import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/core/services/receipt_blob_store.dart';
import 'package:tabby/core/widgets/account_draft_guard.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart'
    as receiving;
import 'package:tabby/features/payment_methods/presentation/payment_methods_sheet.dart';
import 'package:tabby/features/profile/presentation/profile_edit_sheet.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';
import 'package:tabby/features/tabs/presentation/payment_draft_form.dart';

const store = FormDraftStore();
const me = MockTabbyRepository.currentUser;
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==';
final tab = BilateralTab(
    id: 'fixture-tab',
    counterpart: const TabbyUser(
        id: 'fixture-friend',
        displayName: 'Fixture Friend',
        email: '',
        phone: ''),
    netBalanceCentavos: -10000,
    itemCount: 0,
    entries: const [],
    lastUpdated: DateTime(2026));
Future<GlobalKey<NavigatorState>> mount(WidgetTester tester) async {
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
            (_) => CurrentUserNotifier(initialUser: me, autoLoad: false)),
        tabbyProvider.overrideWith((_) => TabbyNotifier(loadInitialData: false))
      ],
      child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('Fixture host')))));
  return nav;
}

Future<void> open(
    WidgetTester tester, GlobalKey<NavigatorState> nav, Widget child) async {
  nav.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: child)));
  await tester.pumpAndSettle();
}

Future<void> keep(WidgetTester tester, GlobalKey<NavigatorState> nav) async {
  await nav.currentState!.maybePop();
  await tester.pumpAndSettle();
  await tester.tap(find.text('Keep draft'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SupabaseConfig.debugUserIdOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
  });
  tearDown(() => SupabaseConfig.debugUserIdOverride = null);
  testWidgets(
      'receiving draft restores stable method and operation IDs after route recreation',
      (tester) async {
    final nav = await mount(tester);
    receiving.PaymentMethodDraft? saved;
    Widget editor() => ReceivingMethodEditor(
        ownerId: me.id,
        onSave: (draft) async {
          saved = draft;
          return false;
        });
    await open(tester, nav, editor());
    await tester.enterText(find.byType(TextField).first, 'Synthetic bank');
    await tester.pumpAndSettle();
    final before = await store.read(me.id, 'receiving:profile:new');
    await keep(tester, nav);
    await open(tester, nav, editor());
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Synthetic bank');
    await tester.tap(find.text('Save Payment Method'));
    await tester.pumpAndSettle();
    expect(saved!.methodId, before!['method']);
    expect(saved!.operationId, before['operation']);
    expect(find.textContaining('Could not verify'), findsOneWidget);
  });
  testWidgets('method changed since draft requires discard before a new edit',
      (tester) async {
    const method = receiving.PaymentMethod(
        id: 'method-fixture',
        ownerUserId: 'user-me',
        provider: 'bank_transfer',
        displayName: 'Synthetic bank',
        accountLabel: '',
        revision: 2);
    await store.write(
        me.id, 'receiving:profile:method-fixture', {'expected_revision': 1});
    final nav = await mount(tester);
    await open(
        tester,
        nav,
        ReceivingMethodEditor(
            ownerId: me.id,
            initial: method,
            onSave: (_) async => fail('stale draft must not save')));
    expect(find.textContaining('could not be restored'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse);
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(await store.read(me.id, 'receiving:profile:method-fixture'), isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'profile edits restore privately and require an acknowledged save',
      (tester) async {
    final nav = await mount(tester);
    Widget editor() => ProfileEditSheet(
        user: me, save: (_, __) async => ProfileUpdateResult.failure);
    await open(tester, nav, editor());
    await tester.enterText(
        find.byType(TextField).first, 'Unsaved fixture name');
    await tester.pumpAndSettle();
    await keep(tester, nav);
    await open(tester, nav, editor());
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Unsaved fixture name');
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Profile'), findsOneWidget);
    final scope = ProviderScope.containerOf(
        tester.element(find.byType(ProfileEditSheet)));
    expect(scope.read(currentUserProvider).displayName, me.displayName);
    expect(await store.read('different-owner', 'profile-edit'), isNull);
  });
  testWidgets(
      'recovered payment image is copied to owned proof bytes without submitting money',
      (tester) async {
    final purpose = 'payment:${tab.id}:${tab.counterpart.id}:false';
    await store.write(me.id, 'picker:$purpose', {
      'id': 'fixture-image',
      'name': 'proof.png',
      'mime': 'image/png',
      'bytes': png
    });
    final nav = await mount(tester);
    await open(tester, nav, PaymentDraftForm(tab: tab, isPayingMe: false));
    expect(find.text('Payment proof attached'), findsOneWidget);
    final draft = await store.read(me.id, purpose);
    expect(
        await ReceiptBlobStore.read(draft!['proof'] as String, ownerId: me.id),
        base64Decode(png));
    expect(await store.read(me.id, 'picker:$purpose'), isNull);
    final scope = ProviderScope.containerOf(
        tester.element(find.byType(PaymentDraftForm)));
    expect(scope.read(tabbyProvider).tabs, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('payment-amount')), '23.45');
    await tester.pumpAndSettle();
    await keep(tester, nav);
    await open(tester, nav, PaymentDraftForm(tab: tab, isPayingMe: false));
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('payment-amount')))
            .controller!
            .text,
        '23.45');
    expect(
        (await store.read(me.id, purpose))!['operation'], draft['operation']);
  });
  testWidgets(
      'recovered expense receipt retains exact draft attachment without creating an expense',
      (tester) async {
    await store.write(me.id, 'picker:expense:new', {
      'id': 'fixture-receipt',
      'name': 'receipt.png',
      'mime': 'image/png',
      'bytes': png
    });
    final nav = await mount(tester);
    await open(tester, nav, const AddExpenseModal());
    final draft = await store.read(me.id, 'expense:new');
    expect(
        await ReceiptBlobStore.read(draft!['receipt'] as String,
            ownerId: me.id),
        base64Decode(png));
    final scope =
        ProviderScope.containerOf(tester.element(find.byType(AddExpenseModal)));
    expect(scope.read(tabbyProvider).tabs, isEmpty);
    await keep(tester, nav);
    await open(tester, nav, const AddExpenseModal());
    expect(
        (await store.read(me.id, 'expense:new'))!['receipt'], draft['receipt']);
  });
  testWidgets(
      'system back returns expense details to people before prompting to leave',
      (tester) async {
    final nav = await mount(tester);
    await open(tester, nav, const AddExpenseModal());
    await tester.enterText(
        find.byKey(const ValueKey('create-tab-unregistered-name')),
        'Synthetic Person');
    await tester.tap(find.text('Add Person'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('create-tab-amount')), '45.67');
    await tester.pumpAndSettle();
    final before = await store.read(me.id, 'expense:new');
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-tab-add-people')), findsOneWidget);
    expect(find.text('Keep this expense draft?'), findsNothing);
    final after = await store.read(me.id, 'expense:new');
    expect(after!['amount'], '45.67');
    expect(after['contact'], before!['contact']);
    expect(after['operation'], before['operation']);
    await keep(tester, nav);
    expect(find.text('Fixture host'), findsOneWidget);
  });
  testWidgets(
      'a corrupt expense draft can be discarded without trapping back navigation',
      (tester) async {
    await store.write(me.id, 'expense:new', {'bad': 'fixture'});
    final nav = await mount(tester);
    await open(tester, nav, const AddExpenseModal());
    expect(find.textContaining('could not be restored'), findsOneWidget);
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture host'), findsOneWidget);
    expect(await store.read(me.id, 'expense:new'), isNull);
  });
  testWidgets(
      'session guard removes its exact old route while preserving the route above',
      (tester) async {
    SupabaseConfig.debugUserIdOverride = 'owner-a';
    final nav = await mount(tester);
    await open(
        tester, nav, const AccountDraftGuard(child: Text('Old account draft')));
    await open(tester, nav, const Text('Replacement overlay'));
    SupabaseConfig.debugUserIdOverride = 'owner-b';
    SupabaseConfig.sessionRevision.value++;
    await tester.pumpAndSettle();
    expect(find.text('Old account draft', skipOffstage: false), findsNothing);
    expect(find.text('Replacement overlay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
