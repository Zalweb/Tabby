import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/services/receipt_attachment_service.dart';
import 'package:tabby/core/services/receipt_blob_store.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==';
Future<String> _pending(String owner) async =>
    (await ReceiptAttachmentService.resolveReceiptUrl(
            file: XFile.fromData(base64Decode(png),
                name: 'receipt.png', mimeType: 'image/png'),
            entryKey: 'fixture',
            ownerId: owner))
        .receiptUrl;
Future<TabbyNotifier> _expense() async {
  final n = TabbyNotifier(loadInitialData: false);
  await n.addExpense(
      counterpartId: 'friend',
      counterpartName: 'Friend',
      title: 'Dinner',
      totalAmountCentavos: 10000,
      category: ExpenseCategory.food,
      paidByMe: true,
      isEqualSplit: false,
      receiptUrl: 'user-me/original.jpg');
  return n;
}

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (call) async => null);
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => SupabaseConfig.debugUserIdOverride = null);
  testWidgets('account change dismisses receipt preview and shared media together',
      (tester) async {
    final n = await _expense();
    final entry = n.state.tabs.single.entries.single;
    await n.attachReceiptToEntry(
        tabId: 'friend', entryId: entry.id,
        receiptUrl: await _pending('user-me'));
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 'friend'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View Receipts'));
    await tester.pumpAndSettle();
    expect(find.text('Shared Media & Receipts'), findsOneWidget);
    await tester.tap(find.byTooltip('View Receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt Preview'), findsOneWidget);
    SupabaseConfig.debugUserIdOverride = 'new-account';
    SupabaseConfig.sessionRevision.value++;
    await tester.pumpAndSettle();
    expect(find.text('Receipt Preview', skipOffstage: false), findsNothing);
    expect(find.text('Shared Media & Receipts', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('receipt preview supports a small phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final n = await _expense();
    final entry = n.state.tabs.single.entries.single;
    await n.attachReceiptToEntry(
        tabId: 'friend', entryId: entry.id,
        receiptUrl: await _pending('user-me'));
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 'friend'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'large-text tab screen');
    await tester.tap(find.byTooltip('View Receipts'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'large-text media list');
    await tester.tap(find.byTooltip('View Receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt Preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('Receipt Preview'), findsNothing);
  });
  test('owned receipt bytes survive picker disposal and reject another owner',
      () async {
    final path = await _pending('owner-a');
    expect(ReceiptBlobStore.isPending(path), isTrue);
    expect(await ReceiptBlobStore.read(path, ownerId: 'owner-a'),
        base64Decode(png));
    expect(
        await ReceiptAttachmentService.readPendingReceiptBytes(path,
            userId: 'owner-a'),
        png);
    await expectLater(
        ReceiptBlobStore.read(path, ownerId: 'owner-b'), throwsStateError);
  });
  test(
      'expense revisions retain original image and durable replay bytes without new money',
      () async {
    final n = await _expense();
    addTearDown(n.dispose);
    final before = n.state.tabs.single.entries.single;
    final path = await _pending('user-me');
    await n.attachReceiptToEntry(
        tabId: 'friend', entryId: before.id, receiptUrl: path);
    final entry = n.state.tabs.single.entries.single;
    expect(entry.id, before.id);
    expect(entry.totalAmountCentavos, before.totalAmountCentavos);
    expect(entry.receiptHistory, ['user-me/original.jpg', path]);
    final op = (await TabbyLocalCache.loadPendingOps(strict: true)).single;
    expect(op['type'], 'append_receipt');
    expect(op['target_kind'], 'transaction');
    expect(op['target_entry_id'], before.id);
    expect(op['proof_bytes'], png);
    expect(
        (await TabbyLocalCache.loadTabs())!
            .single
            .entries
            .single
            .receiptHistory,
        entry.receiptHistory);
  });
  test(
      'server receipt revisions retain initial path and choose newest display image',
      () {
    final tab = SupabaseTabbyRepository.parseTabRow({
      'id': 't',
      'tab_members': [
        {'user_id': 'user-me'},
        {'user_id': 'friend'}
      ],
      'transactions': [
        {
          'id': 'tx',
          'created_by': 'user-me',
          'total_amount_centavos': 100,
          'receipt_url': 'owner/original.jpg',
          'transaction_receipt_revisions': [
            {
              'storage_path': 'owner/later.png',
              'uploaded_at': '2026-11-01T02:00:00Z'
            },
            {
              'storage_path': 'owner/earlier.png',
              'uploaded_at': '2026-11-01T01:00:00Z'
            }
          ]
        }
      ]
    }, 'user-me')!;
    expect(tab.entries.single.receiptHistory,
        ['owner/original.jpg', 'owner/earlier.png', 'owner/later.png']);
    expect(tab.entries.single.receiptUrl, 'owner/later.png');
  });
  test('picker completion follows durable local-to-server mapping after sync',
      () async {
    final n = await _expense();
    addTearDown(n.dispose);
    final local = n.state.tabs.single.entries.single;
    const remote = '00000000-0000-4000-8000-000000000321';
    await TabbyLocalCache.saveEntryMapping(local.id, remote, 'remote-tab',
        userId: 'offline');
    n.state = n.state.copyWith(tabs: [
      n.state.tabs.single.copyWith(
          id: 'remote-tab',
          entries: [local.copyWith(id: remote, tabId: 'remote-tab')])
    ]);
    await n.attachReceiptToEntry(
        tabId: 'friend',
        entryId: local.id,
        receiptUrl: await _pending('user-me'));
    final op = (await TabbyLocalCache.loadPendingOps(strict: true)).single;
    expect(op['target_entry_id'], remote);
    expect(n.state.tabs.single.entries.single.id, remote);
    expect(
        await TabbyLocalCache.loadEntryMapping(local.id,
            userId: 'another-user'),
        isNull);
  });
  testWidgets(
      'receipt preview renders owned image and exposes earlier receipt without verification claim',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final n = await _expense();
    final entry = n.state.tabs.single.entries.single;
    await n.attachReceiptToEntry(
        tabId: 'friend',
        entryId: entry.id,
        receiptUrl: await _pending('user-me'));
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 'friend'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dinner'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verified'), findsNothing);
    final current = find.text('Receipt attached (tap to view)');
    await tester.ensureVisible(current);
    await tester.tap(current);
    await tester.pumpAndSettle();
    final memoryImage =
        find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage);
    expect(memoryImage, findsOneWidget);
    final image = tester.widget<Image>(memoryImage);
    await tester.runAsync(
        () => precacheImage(image.image, tester.element(memoryImage)));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((w) =>
            w is RawImage && w.image?.width == 1 && w.image?.height == 1),
        findsOneWidget);
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    final earlier = find.text('Earlier receipt 1');
    await tester.ensureVisible(earlier);
    await tester.tap(earlier);
    await tester.pumpAndSettle();
    expect(find.text('Receipt Preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
