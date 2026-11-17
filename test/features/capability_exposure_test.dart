import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

class _Notifier extends TabbyNotifier {
  _Notifier(TransactionStatus status) : super(loadInitialData: false) {
    state = state.copyWith(tabs: [
      BilateralTab(
        id: 'capability-tab',
        counterpart: const TabbyUser(
            id: 'friend', displayName: 'Friend', email: '', phone: ''),
        entries: [
          LedgerEntry(
              id: 'expense',
              tabId: 'capability-tab',
              title: 'Dinner fixture',
              category: ExpenseCategory.food,
              totalAmountCentavos: 10001,
              myShareCentavos: 5000,
              counterpartShareCentavos: 5001,
              paidByUserId: 'user-me',
              paidByName: 'You',
              date: DateTime(2026),
              status: status)
        ],
        itemCount: 1,
        netBalanceCentavos: 5001,
        lastUpdated: DateTime(2026),
      )
    ]);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final status in [
    TransactionStatus.pending,
    TransactionStatus.acknowledged
  ]) {
    testWidgets('expense status $status does not imply counterpart consent',
        (tester) async {
      final notifier = _Notifier(status);
      await tester.pumpWidget(ProviderScope(
          overrides: [tabbyProvider.overrideWith((ref) => notifier)],
          child: const MaterialApp(
              home: TabDetailScreen(tabId: 'capability-tab'))));
      await tester.pumpAndSettle();
      expect(find.text('Recorded'), findsOneWidget);
      expect(find.text('Acknowledged'), findsNothing);
      expect(find.text('Pending Ack'), findsNothing);
      await tester.tap(find.text('Dinner fixture'));
      await tester.pumpAndSettle();
      for (final unsupported in [
        'Acknowledge',
        'Dispute',
        'Propose amount',
        'Custom split',
        'Repeat expense'
      ]) {
        expect(find.text(unsupported), findsNothing);
      }
      expect(notifier.state.tabs.single.entries.single.status, status);
      expect(notifier.state.tabs.single.netBalanceCentavos, 5001);
    });
  }

  test('published landing mirrors describe actual splits and group obligations',
      () {
    final landing = File('landing/index.html').readAsStringSync();
    final mirror = File('docs/index.html').readAsStringSync();
    expect(landing, mirror);
    expect(landing, contains('choose the actual payer'));
    expect(landing, contains('share stays in the group history'));
    expect(
        landing, contains('Custom individual amounts are not available yet.'));
    expect(landing, isNot(contains('pick equal or custom split')));
    expect(landing, isNot(contains('customize individual centavo amounts')));
    expect(
        landing,
        isNot(
            contains("each member's share into their bilateral running tab")));
  });
}
