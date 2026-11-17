import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/data/ledger_cache_storage.dart';
import 'package:tabby/features/tabs/data/ledger_key_value_store.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

const paymentId = '00000000-0000-4000-8000-000000000077';

class _Notifier extends TabbyNotifier {
  _Notifier(Future<String?> Function(String, bool, String?) writer,
      {bool incoming = true,
      super.tabLoader})
      : super(loadInitialData: false, paymentDecision: writer) {
    state = state.copyWith(tabs: [
      BilateralTab(
          id: 't',
          counterpart: const TabbyUser(
              id: 'friend', displayName: 'Friend', email: '', phone: ''),
          entries: [
            LedgerEntry(
                id: 'expense',
                tabId: 't',
                title: 'Dinner',
                category: ExpenseCategory.food,
                totalAmountCentavos: 5000,
                myShareCentavos: 0,
                counterpartShareCentavos: 5000,
                paidByUserId: 'user-me',
                paidByName: 'You',
                date: DateTime(2026)),
            LedgerEntry(
                id: paymentId,
                tabId: 't',
                title: 'Pending transfer',
                category: ExpenseCategory.other,
                totalAmountCentavos: 2000,
                myShareCentavos: 0,
                counterpartShareCentavos: 0,
                paidByUserId: incoming ? 'friend' : 'user-me',
                paidByName: 'Friend',
                date: DateTime(2026),
                payer: PartyRef(
                    kind: PartyKind.user, id: incoming ? 'friend' : 'user-me'),
                recipient: PartyRef(
                    kind: PartyKind.user, id: incoming ? 'user-me' : 'friend'),
                isPayment: true,
                status: TransactionStatus.paymentSubmitted)
          ],
          itemCount: 2,
          netBalanceCentavos: 5000,
          lastUpdated: DateTime(2026))
    ]);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('manual receipt cannot manufacture a confirmed wallet payment',
      () async {
    final n = _Notifier((id, c, r) async => id);
    addTearDown(n.dispose);
    await expectLater(
        n.settleTab(
            tabId: 't',
            amountCentavos: 1000,
            method: PaymentMethod.gcash,
            isPayingMe: true),
        throwsA(anything));
    expect(n.state.tabs.single.entries, hasLength(2));
  });
  tearDown(() => SupabaseConfig.debugUserIdOverride = null);
  test(
      'specific confirmation waits for acknowledgment and preserves one submission',
      () async {
    final ack = Completer<String?>();
    var calls = 0;
    final n = _Notifier((id, confirm, reason) async {
      calls++;
      expect(id, paymentId);
      expect(confirm, isTrue);
      return ack.future;
    });
    addTearDown(n.dispose);
    final decision = n.decidePayment(paymentId, confirm: true);
    await Future<void>.delayed(Duration.zero);
    expect(n.state.tabs.single.entries.last.status,
        TransactionStatus.paymentSubmitted);
    ack.complete(paymentId);
    await decision;
    await n.decidePayment(paymentId, confirm: true);
    expect(calls, 2);
    expect(n.state.tabs.single.entries, hasLength(2));
    expect(n.state.tabs.single.entries.last.id, paymentId);
    expect(n.state.tabs.single.netBalanceCentavos, 3000);
    expect((await TabbyLocalCache.loadTabs())!.single.entries.last.status,
        TransactionStatus.settled);
  });
  test('rejection retains original amount, ID and reason without reducing debt',
      () async {
    final n = _Notifier((id, confirm, reason) async {
      expect(confirm, isFalse);
      expect(reason, 'Incorrect amount');
      return id;
    });
    addTearDown(n.dispose);
    await n.decidePayment(paymentId,
        confirm: false, reason: ' Incorrect amount ');
    final e = n.state.tabs.single.entries.last;
    expect(e.id, paymentId);
    expect(e.totalAmountCentavos, 2000);
    expect(e.status, TransactionStatus.cancelled);
    expect(e.rejectionReason, 'Incorrect amount');
    expect(n.state.tabs.single.netBalanceCentavos, 5000);
    expect(
        (await TabbyLocalCache.loadTabs())!.single.entries.last.rejectionReason,
        'Incorrect amount');
  });
  test('failed decision and nonrecipient never change the ledger', () async {
    final n = _Notifier((id, c, r) async => null);
    addTearDown(n.dispose);
    await expectLater(
        n.decidePayment(paymentId, confirm: true), throwsStateError);
    expect(n.state.tabs.single.entries.last.status,
        TransactionStatus.paymentSubmitted);
    var called = false;
    final payer = _Notifier((id, c, r) async {
      called = true;
      return id;
    }, incoming: false);
    addTearDown(payer.dispose);
    await expectLater(
        payer.decidePayment(paymentId, confirm: true), throwsA(anything));
    expect(called, isFalse);
  });
  test('late decision acknowledgment cannot commit into a changed session',
      () async {
    final ack = Completer<String?>();
    final n = _Notifier((id, c, r) => ack.future);
    addTearDown(n.dispose);
    final decision = n.decidePayment(paymentId, confirm: true);
    SupabaseConfig.debugUserIdOverride = 'other-session';
    ack.complete(paymentId);
    await expectLater(decision, throwsStateError);
    expect(n.state.tabs.single.entries.last.status,
        TransactionStatus.paymentSubmitted);
  });
  for (final checkpoint in ['tabs', 'activities', 'reminders']) {
    test('account change during $checkpoint persistence cannot report success',
        () async {
      final original = LedgerCacheStorage.debugOverride;
      final blocked = _BlockedCache(checkpoint);
      LedgerCacheStorage.debugOverride = blocked;
      addTearDown(() => LedgerCacheStorage.debugOverride = original);
      SupabaseConfig.debugUserIdOverride = 'user-me';
      final n = _Notifier((id, _, __) async => id);
      addTearDown(n.dispose);
      final decision = n.decidePayment(paymentId, confirm: true);
      final rejected = expectLater(decision, throwsStateError);
      await blocked.started.future;
      SupabaseConfig.debugUserIdOverride = 'new-account';
      blocked.release.complete();
      await rejected;
      expect(await TabbyLocalCache.loadTabs(userId: 'new-account'), isNull);
    });
  }
  test('older refresh cannot replace a newer confirmed payment snapshot',
      () async {
    final old = Completer<List<BilateralTab>>();
    final firstRead = Completer<void>();
    var reads = 0;
    late BilateralTab pending, confirmed;
    final n = _Notifier((id, _, __) async => id, tabLoader: (_) {
      if (reads++ == 0) {
        firstRead.complete();
        return old.future;
      }
      return Future.value([confirmed]);
    });
    addTearDown(n.dispose);
    pending = n.state.tabs.single;
    confirmed = pending.copyWith(entries: [
      pending.entries.first,
      pending.entries.last.copyWith(status: TransactionStatus.settled),
    ], netBalanceCentavos: 3000);
    final previous = n.synchronize();
    await firstRead.future;
    await n.synchronize();
    expect(n.state.tabs.single.netBalanceCentavos, 3000);
    old.complete([pending]);
    final discarded = await previous;
    expect(n.state.tabs.single.netBalanceCentavos, 3000);
    expect(n.state.tabs.single.entries.last.status, TransactionStatus.settled);
    expect(discarded.localSaved, isFalse);
    expect((await TabbyLocalCache.loadTabs())!.single.netBalanceCentavos, 3000);
  });
  test('refresh started before a payment decision cannot undo its acknowledgment',
      () async {
    final stale = Completer<List<BilateralTab>>();
    final started = Completer<void>();
    final n = _Notifier((id, _, __) async => id, tabLoader: (_) {
      started.complete();
      return stale.future;
    });
    addTearDown(n.dispose);
    final pending = n.state.tabs.single;
    final refreshing = n.synchronize();
    await started.future;
    await n.decidePayment(paymentId, confirm: true);
    expect(n.state.tabs.single.netBalanceCentavos, 3000);
    stale.complete([pending]);
    await refreshing;
    expect(n.state.tabs.single.netBalanceCentavos, 3000);
    expect(n.state.tabs.single.entries.last.status, TransactionStatus.settled);
  });
  testWidgets('entry details disappear on account change', (tester) async {
    final n = _Notifier((id, _, __) async => id);
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 't'))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pending transfer'));
    await tester.tap(find.text('Pending transfer'));
    await tester.pumpAndSettle();
    expect(find.text('Payment Details'), findsOneWidget);
    SupabaseConfig.debugUserIdOverride = 'new-account';
    SupabaseConfig.sessionRevision.value++;
    await tester.pumpAndSettle();
    expect(find.text('Payment Details'), findsNothing);
    expect(find.text('Confirm Payment'), findsNothing);
  });
  testWidgets('reminder sheet disappears on account change', (tester) async {
    final n = _Notifier((id, _, __) async => id);
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 't'))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remind Friend'));
    await tester.tap(find.text('Remind Friend'));
    await tester.pumpAndSettle();
    expect(find.text('Send In-App Reminder'), findsOneWidget);
    SupabaseConfig.debugUserIdOverride = 'new-account';
    SupabaseConfig.sessionRevision.value++;
    await tester.pumpAndSettle();
    expect(find.text('Send In-App Reminder', skipOffstage: false), findsNothing);
  });
  testWidgets('group obligation sheet disappears on account change',
      (tester) async {
    final n = _Notifier((id, _, __) async => id);
    n.state = n.state.copyWith(tabs: [n.state.tabs.single.copyWith(
      isGroupTab: true, groupName: 'Fixture group',
      entries: [], netBalanceCentavos: 0,
    )]);
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 't'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Payment Info'));
    await tester.pumpAndSettle();
    expect(find.text('No outstanding group obligations.'), findsNWidgets(2));
    SupabaseConfig.debugUserIdOverride = 'new-account';
    SupabaseConfig.sessionRevision.value++;
    await tester.pumpAndSettle();
    expect(find.text('No outstanding group obligations.', skipOffstage: false),
        findsOneWidget);
  });
  testWidgets('confirmation closes its own sheet and preserves a newer dialog',
      (tester) async {
    final reply = Completer<String?>();
    final navigator = GlobalKey<NavigatorState>();
    final n = _Notifier((_, __, ___) => reply.future);
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: MaterialApp(
            navigatorKey: navigator, home: const TabDetailScreen(tabId: 't'))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pending transfer'));
    await tester.tap(find.text('Pending transfer'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm Payment'));
    await tester.tap(find.text('Confirm Payment'));
    await tester.pump();
    unawaited(showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: Text('Keep this dialog')),
    ));
    await tester.pump();
    reply.complete(paymentId);
    await tester.pumpAndSettle();
    expect(find.text('Keep this dialog'), findsOneWidget);
    expect(find.text('Payment Details', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('recipient confirms original submission from its detail sheet',
      (tester) async {
    var requested = '';
    var calls = 0;
    final n = _Notifier((id, c, r) async {
      requested = id;
      calls++;
      return id;
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: TabDetailScreen(tabId: 't'))));
    await tester.pumpAndSettle();
    final entry = find.text('Pending transfer');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final confirm = find.text('Confirm Payment');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(requested, paymentId);
    expect(calls, 1);
    expect(n.state.tabs.single.entries, hasLength(2));
    expect(n.state.tabs.single.netBalanceCentavos, 3000);
    expect(tester.takeException(), isNull);
  });
}

class _BlockedCache implements LedgerKeyValueStore {
  _BlockedCache(this.layer);
  final String layer;
  final started = Completer<void>(), release = Completer<void>();
  final LedgerKeyValueStore delegate = const SecureLedgerKeyValueStore();
  @override
  Future<String?> read({required String key}) => delegate.read(key: key);
  @override
  Future<void> removeValue({required String key}) => delegate.removeValue(key: key);
  @override
  Future<void> write({required String key, required String value}) async {
    if (key.startsWith('tabby_cached_${layer}_') && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    await delegate.write(key: key, value: value);
  }
}
