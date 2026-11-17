import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';
import 'package:uuid/uuid.dart';

Future<TabbyNotifier> _owing() async {
  final n = TabbyNotifier(loadInitialData: false);
  await n.addExpense(
      counterpartId: 'friend',
      counterpartName: 'Friend',
      title: 'Debt',
      totalAmountCentavos: 10000,
      category: ExpenseCategory.other,
      paidByMe: false,
      isEqualSplit: false,
      isConnectedFriend: true);
  return n;
}

Future<File> _image() async {
  final f = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}tabby-proof-${const Uuid().v4()}.png');
  await f.writeAsBytes(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='));
  addTearDown(() async {
    if (await f.exists()) await f.delete();
  });
  return f;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'payment captures durable proof bytes and reference before temporary file loss',
      () async {
    final n = await _owing();
    addTearDown(n.dispose);
    final file = await _image();
    final bytes = await file.readAsBytes();
    await n.settleTab(
        tabId: 'friend',
        amountCentavos: 2000,
        method: PaymentMethod.gcash,
        isPayingMe: false,
        proofPath: file.path,
        paymentReference: 'Synthetic reference');
    final payment = n.state.tabs.single.entries.first;
    expect(payment.isPayment, isTrue);
    expect(payment.paymentReference, 'Synthetic reference');
    expect(payment.status, TransactionStatus.paymentSubmitted);
    expect(n.state.tabs.single.netBalanceCentavos, -10000);
    await file.delete();
    final op = (await TabbyLocalCache.loadPendingOps(strict: true)).single;
    expect(op['local_entry_id'], payment.id);
    expect(base64Decode(op['proof_bytes'] as String), bytes);
    expect(
        (await TabbyLocalCache.loadTabs())!
            .single
            .entries
            .first
            .paymentReference,
        'Synthetic reference');
  });
  test(
      'later proof keeps payment target mapping and freezes append command across retry',
      () async {
    final n = await _owing();
    addTearDown(n.dispose);
    final file = await _image();
    await n.settleTab(
        tabId: 'friend',
        amountCentavos: 2000,
        method: PaymentMethod.cash,
        isPayingMe: false,
        paymentReference: 'Original reference');
    final payment = n.state.tabs.single.entries.first;
    await n.attachReceiptToEntry(
        tabId: 'friend', entryId: payment.id, receiptUrl: file.path);
    var ops = await TabbyLocalCache.loadPendingOps(strict: true);
    expect(ops, hasLength(2));
    final revision = ops.singleWhere((o) => o['type'] == 'append_receipt');
    const remote = '00000000-0000-4000-8000-000000000123';
    await TabbyLocalCache.remapPendingProofTargets(payment.id, remote,
        userId: 'offline');
    ops = await TabbyLocalCache.loadPendingOps(strict: true);
    expect(
        ops.singleWhere(
            (o) => o['type'] == 'append_receipt')['target_entry_id'],
        remote);
    final first = await TabbyLocalCache.prepareProofCommand(
        revision['operation_id'] as String,
        userId: 'offline',
        command: {'payment_id': remote, 'proof_path': 'owner/immutable.png'});
    final retry = await TabbyLocalCache.prepareProofCommand(
        revision['operation_id'] as String,
        userId: 'offline',
        command: {'payment_id': remote, 'proof_path': 'owner/changed.png'});
    expect(retry, first);
    expect(n.state.tabs.single.entries.where((e) => e.isPayment), hasLength(1));
  });
  test('parse reads newest image and reference from payment proof revisions',
      () {
    final tab = SupabaseTabbyRepository.parseTabRow({
      'id': 't',
      'tab_members': [
        {'user_id': 'user-me'},
        {'user_id': 'friend'}
      ],
      'payments': [
        {
          'id': 'p',
          'submitted_by': 'friend',
          'recipient_user_id': 'user-me',
          'amount_centavos': 100,
          'status': 'submitted',
          'payment_proofs': [
            {
              'file_url': 'owner/old.png',
              'reference': 'Old',
              'uploaded_at': '2026-10-31T01:00:00Z'
            },
            {
              'file_url': 'owner/new.png',
              'reference': 'New',
              'uploaded_at': '2026-11-01T01:00:00Z'
            }
          ]
        }
      ]
    }, 'user-me')!;
    expect(tab.entries.single.receiptUrl, 'owner/new.png');
    expect(tab.entries.single.paymentReference, 'New');
    expect(tab.entries.single.status, TransactionStatus.paymentSubmitted);
  });
  testWidgets(
      'payment form saves an optional reference on its payment, not the expense',
      (tester) async {
    final n = await _owing();
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 'friend'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I Paid'));
    await tester.pumpAndSettle();
    expect(find.text('Attach payment proof (optional)'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Payment reference (optional)'),
        'Synthetic reference');
    final submit = find.text('Submit Payment Proof');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(n.state.tabs.single.entries.first.paymentReference,
        'Synthetic reference');
    expect(n.state.tabs.single.entries.last.paymentReference, isNull);
    expect(n.state.tabs.single.entries.first.status,
        TransactionStatus.paymentSubmitted);
    expect(tester.takeException(), isNull);
  });
}
