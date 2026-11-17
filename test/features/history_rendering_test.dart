import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

class HistoryNotifier extends TabbyNotifier {
  HistoryNotifier(BilateralTab tab) : super(loadInitialData: false) {
    state = state.copyWith(tabs: [tab], activities: [], reminders: []);
  }
}

void main() {
  testWidgets(
    'detail reveals older history only when another page is requested',
    (tester) async {
      final tab = BilateralTab.fromMap({
        'id': 'history',
        'netBalanceCentavos': 5100,
        'entries': List.generate(
          51,
          (i) => {
            'id': 'fixture-$i',
            'tabId': 'history',
            'title': 'History fixture $i',
            'totalAmountCentavos': 100,
            'paidByUserId': 'user-me',
            'paidByName': 'Synthetic owner',
            'date': DateTime.utc(
              2026,
              11,
              2,
            ).subtract(Duration(minutes: i)).toIso8601String(),
          },
        ),
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [tabbyProvider.overrideWith((_) => HistoryNotifier(tab))],
          child: MaterialApp(home: TabDetailScreen(tabId: tab.id)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('History fixture 50'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Load older records'),
        300,
        scrollable: find.descendant(
          of: find.byType(ListView), matching: find.byType(Scrollable)),
        maxScrolls: 50,
      );
      await tester.tap(find.text('Load older records'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('History fixture 50'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView), matching: find.byType(Scrollable)),
      );
      expect(find.text('History fixture 50'), findsOneWidget);
      expect(find.text('Load older records'), findsNothing);
    },
  );
}
