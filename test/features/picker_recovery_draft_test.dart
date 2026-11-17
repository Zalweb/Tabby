import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/core/services/picker_recovery.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';

const storage = FlutterSecureStorage();
const drafts = FormDraftStore();
XFile image([int value = 1]) =>
    XFile.fromData(Uint8List.fromList([value, 2, 3]),
        name: 'synthetic.png', mimeType: 'image/png');
PickerRecovery recovery(
        {Future<XFile?> Function(ImageSource)? pick,
        Future<LostDataResponse> Function()? retrieve,
        FlutterSecureStorage? disk}) =>
    PickerRecovery(
        pick: pick ?? (_) async => image(),
        retrieve: retrieve ?? () async => LostDataResponse.empty(),
        storage: disk ?? storage);
Future<void> intent({String owner = 'a', String purpose = 'expense:new'}) =>
    storage.write(
        key: PickerRecovery.intentKey,
        value: jsonEncode(
            {'id': 'fixture-operation', 'owner': owner, 'purpose': purpose}));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
  });
  test(
      'intent is durable before picker launch and image is copied before return',
      () async {
    final r = recovery(pick: (_) async {
      expect(
          jsonDecode(
              (await storage.read(key: PickerRecovery.intentKey))!)['owner'],
          'a');
      return image();
    });
    final picked = await r.select(
        owner: 'a',
        purpose: 'expense:new',
        source: ImageSource.gallery,
        isCurrent: () => true);
    expect(picked!.path, startsWith('tabby-picker:'));
    expect(await storage.read(key: PickerRecovery.intentKey), isNull);
    final restart = recovery();
    expect(await (await restart.restored('a', 'expense:new'))!.readAsBytes(),
        [1, 2, 3]);
    expect(await restart.restored('b', 'expense:new'), isNull);
    expect(await restart.restored('a', 'avatar'), isNull);
    await restart.acknowledge('a', 'expense:new', picked);
    expect(await restart.restored('a', 'expense:new'), isNull);
  });
  test('startup lost data uses original owner and exact workflow', () async {
    await intent();
    var calls = 0;
    final r = recovery(retrieve: () async {
      calls++;
      return LostDataResponse(files: [image()]);
    });
    await Future.wait([r.recover(), r.recover()]);
    expect(calls, 1);
    expect(await r.restored('b', 'expense:new'), isNull);
    expect(
        await (await r.restored('a', 'expense:new'))!.readAsBytes(), [1, 2, 3]);
    expect(calls, 1);
  });
  test('unattributed lost image never guesses an account', () async {
    final r =
        recovery(retrieve: () async => LostDataResponse(files: [image()]));
    await r.recover();
    expect(await r.restored('a', 'expense:new'), isNull);
  });
  test(
      'account change during picker keeps A result private and returns nothing to B',
      () async {
    final pending = Completer<XFile?>(), started = Completer<void>();
    var current = true;
    final r = recovery(pick: (_) {
      started.complete();
      return pending.future;
    });
    final call = r.select(
        owner: 'a',
        purpose: 'avatar',
        source: ImageSource.camera,
        isCurrent: () => current);
    await started.future;
    current = false;
    pending.complete(image());
    expect(await call, isNull);
    expect(await r.restored('b', 'avatar'), isNull);
    expect(await r.restored('a', 'avatar'), isNotNull);
  });
  test(
      'cancellation clears attribution and cannot revive an unrelated later result',
      () async {
    final r = recovery(pick: (_) async => null);
    expect(
        await r.select(
            owner: 'a',
            purpose: 'avatar',
            source: ImageSource.camera,
            isCurrent: () => true),
        isNull);
    expect(await storage.read(key: PickerRecovery.intentKey), isNull);
  });
  test('old acknowledgment preserves a newer image for same workflow',
      () async {
    var value = 1;
    final r = recovery(pick: (_) async => image(value++));
    final old = await r.select(
        owner: 'a',
        purpose: 'avatar',
        source: ImageSource.gallery,
        isCurrent: () => true);
    await r.select(
        owner: 'a',
        purpose: 'avatar',
        source: ImageSource.gallery,
        isCurrent: () => true);
    await r.acknowledge('a', 'avatar', old!);
    expect(await (await r.restored('a', 'avatar'))!.readAsBytes(), [2, 2, 3]);
  });
  test('native recovery error remains visible and does not fabricate an image',
      () async {
    await intent();
    final r = recovery(
        retrieve: () async =>
            LostDataResponse(exception: PlatformException(code: 'synthetic')));
    await r.recover();
    await expectLater(r.restored('a', 'expense:new'), throwsFormatException);
    expect(await r.restored('b', 'expense:new'), isNull);
  });
  test('failed intent persistence never opens picker and remains retryable',
      () async {
    final disk = FailingDraftStorage()..fail = true;
    var calls = 0;
    final r = recovery(
        disk: disk,
        pick: (_) async {
          calls++;
          return image();
        });
    await expectLater(
        r.select(
            owner: 'a',
            purpose: 'avatar',
            source: ImageSource.gallery,
            isCurrent: () => true),
        throwsStateError);
    expect(calls, 0);
    disk.fail = false;
    expect(
        await r.select(
            owner: 'a',
            purpose: 'avatar',
            source: ImageSource.gallery,
            isCurrent: () => true),
        isNotNull);
  });
  test(
      'form removal follows queued writes and account/workflow remain separate',
      () async {
    await drafts.write('a', 'expense:new', {'amount': '12.34'});
    final write = drafts.write('a', 'expense:new', {'amount': '56.78'});
    final remove = drafts.remove('a', 'expense:new');
    await Future.wait([write, remove]);
    expect(await drafts.read('a', 'expense:new'), isNull);
    await drafts.write('a', 'expense:new', {'amount': '12.34'});
    expect(await drafts.read('b', 'expense:new'), isNull);
    expect(await drafts.read('a', 'payment:tab'), isNull);
  });
  test('discard removes a recovered image without changing another workflow',
      () async {
    final r = recovery();
    await r.select(
        owner: 'a',
        purpose: 'avatar',
        source: ImageSource.gallery,
        isCurrent: () => true);
    await r.select(
        owner: 'a',
        purpose: 'expense:new',
        source: ImageSource.gallery,
        isCurrent: () => true);
    await r.discard('a', 'expense:new');
    expect(await r.restored('a', 'expense:new'), isNull);
    expect(await r.restored('a', 'avatar'), isNotNull);
  });
  test('a failed result write retains the same captured image for retry',
      () async {
    final disk = FailingDraftStorage()..failResult = true;
    var calls = 0;
    final r = recovery(
        disk: disk,
        pick: (_) async {
          calls++;
          return image();
        });
    await expectLater(
        r.select(
            owner: 'a',
            purpose: 'avatar',
            source: ImageSource.gallery,
            isCurrent: () => true),
        throwsStateError);
    disk.failResult = false;
    await r.recover();
    expect(await (await r.restored('a', 'avatar'))!.readAsBytes(), [1, 2, 3]);
    expect(calls, 1);
  });
  test('invalid image size releases the picker for a valid replacement',
      () async {
    var invalid = true;
    final r = recovery(
        pick: (_) async => invalid
            ? XFile.fromData(Uint8List(0), name: 'empty.png')
            : image());
    await expectLater(
        r.select(
            owner: 'a',
            purpose: 'avatar',
            source: ImageSource.gallery,
            isCurrent: () => true),
        throwsFormatException);
    invalid = false;
    expect(
        await r.select(
            owner: 'a',
            purpose: 'avatar',
            source: ImageSource.gallery,
            isCurrent: () => true),
        isNotNull);
  });
  test(
      'cash retry after a zero balance reuses its original payment exactly once',
      () async {
    final n = TabbyNotifier(loadInitialData: false);
    addTearDown(n.dispose);
    await n.addExpense(
        counterpartId: 'fixture-friend',
        counterpartName: 'Fixture Friend',
        title: 'Synthetic expense',
        totalAmountCentavos: 1234,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false);
    Future<void> submit(int cents) => n.settleTab(
        operationId: '00000000-0000-4000-8000-000000000002',
        tabId: n.state.tabs.single.id,
        amountCentavos: cents,
        method: PaymentMethod.cash,
        isPayingMe: true);
    await submit(1234);
    expect(n.state.tabs.single.netBalanceCentavos, 0);
    await submit(1234);
    expect(n.state.tabs.single.entries.where((e) => e.isPayment).length, 1);
    await expectLater(submit(1233), throwsStateError);
  });
  test(
      'retained expense operation cannot duplicate local history or change intent',
      () async {
    final n = TabbyNotifier(loadInitialData: false);
    addTearDown(n.dispose);
    Future<void> submit(int amount) => n.addExpense(
        operationId: '00000000-0000-4000-8000-000000000001',
        counterpartId: 'fixture-contact',
        counterpartName: 'Fixture Contact',
        title: 'Synthetic expense',
        totalAmountCentavos: amount,
        category: ExpenseCategory.food,
        paidByMe: true,
        isEqualSplit: false);
    await submit(1234);
    await submit(1234);
    expect(n.state.tabs.single.entries.length, 1);
    await expectLater(submit(4321), throwsStateError);
    expect(n.state.tabs.single.entries.single.totalAmountCentavos, 1234);
  });
  testWidgets(
      'expense draft survives route recreation and system back asks before discard',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          tabbyProvider
              .overrideWith((_) => TabbyNotifier(loadInitialData: false)),
          currentUserProvider.overrideWith((_) => CurrentUserNotifier(
              initialUser: MockTabbyRepository.currentUser, autoLoad: false))
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Fixture host')))));
    void open() => navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: AddExpenseModal())));
    open();
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('create-tab-unregistered-name'));
    await tester.enterText(name, 'Draft Person');
    await tester.pumpAndSettle();
    expect(await navigator.currentState!.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Keep this expense draft?'), findsOneWidget);
    await tester.tap(find.text('Keep draft'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture host'), findsOneWidget);
    open();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(name).controller!.text, 'Draft Person');
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    open();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(name).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class FailingDraftStorage extends FlutterSecureStorage {
  bool fail = false, failResult = false;
  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (fail || (failResult && key.startsWith('tabby_form_v1_'))) {
      throw StateError('Synthetic disk failure');
    }
    await super.write(
        key: key,
        value: value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions);
  }
}
