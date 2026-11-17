import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';
import 'package:tabby/shared/widgets/tabby_button.dart';

const me = MockTabbyRepository.currentUser;
const friend = TabbyUser(
  id: 'friend-qa',
  displayName: 'Alex',
  email: '',
  phone: '',
  friendCode: 'TAB-QATEST',
);
const second = TabbyUser(
  id: 'friend-two',
  displayName: 'Alex',
  email: '',
  phone: '',
  friendCode: 'TAB-QATWO',
);

class EntryLedger extends TabbyNotifier {
  EntryLedger({
    bool existing = true,
    bool group = false,
    bool withExpense = true,
  }) : super(loadInitialData: false) {
    state = state.copyWith(
      tabs: existing
          ? [
              BilateralTab(
                id: 'shared-tab',
                counterpart: friend,
                isGroupTab: group,
                members: group ? [me, friend, second] : const [],
                groupName: group ? 'Custom group' : null,
                netBalanceCentavos: withExpense ? 15000 : 0,
                itemCount: withExpense ? 1 : 0,
                entries: withExpense
                    ? [
                        LedgerEntry(
                          id: 'saved-expense',
                          tabId: 'shared-tab',
                          title: 'Loan',
                          category: ExpenseCategory.food,
                          totalAmountCentavos: 15000,
                          myShareCentavos: 0,
                          counterpartShareCentavos: 15000,
                          paidByUserId: me.id,
                          paidByName: 'You',
                          date: DateTime.now(),
                        ),
                      ]
                    : [],
                lastUpdated: DateTime.now(),
              ),
            ]
          : [],
      activities: [],
      reminders: [],
      friendRequests: [],
    );
  }
  bool failLookup = false;
  Completer<BilateralTab?>? lookup;
  @override
  Future<BilateralTab?> inspectSharedTab(String otherUserId) async {
    if (failLookup) throw StateError('Synthetic offline');
    if (lookup != null) return lookup!.future;
    return super.inspectSharedTab(otherUserId);
  }
}

class ResponseLostLedger extends EntryLedger {
  final operations = <String?>[];
  @override
  Future<void> addExpense({
    String? operationId,
    required String counterpartId,
    required String counterpartName,
    required String title,
    required int totalAmountCentavos,
    required ExpenseCategory category,
    required bool paidByMe,
    required bool isEqualSplit,
    bool isConnectedFriend = false,
    int participantCount = 2,
    String? payerId,
    String? payerName,
    DateTime? dueDate,
    String? receiptUrl,
    Map<String, int>? customAmounts,
  }) async {
    operations.add(operationId);
    await super.addExpense(
      operationId: operationId,
      counterpartId: counterpartId,
      counterpartName: counterpartName,
      title: title,
      totalAmountCentavos: totalAmountCentavos,
      category: category,
      paidByMe: paidByMe,
      isEqualSplit: isEqualSplit,
      isConnectedFriend: isConnectedFriend,
      participantCount: participantCount,
      payerId: payerId,
      payerName: payerName,
      dueDate: dueDate,
      receiptUrl: receiptUrl,
      customAmounts: customAmounts,
    );
    if (operations.length == 1) {
      throw TimeoutException('Synthetic lost response after durable handoff');
    }
  }
}

Future<void> mount(
  WidgetTester tester,
  EntryLedger ledger, {
  String? initial,
  bool routed = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(440, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Widget launcher() => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () =>
            AddExpenseModal.show(context, initialCounterpartId: initial),
        child: const Text('Open'),
      ),
    ),
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => launcher()),
      GoRoute(
        path: '/tabs/:id',
        builder: (_, state) =>
            Scaffold(body: Text('History ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tabbyProvider.overrideWith((_) => ledger),
        friendsProvider.overrideWith((_) => [friend, second]),
      ],
      child: routed
          ? MaterialApp.router(
              theme: TabbyTheme.lightTheme,
              routerConfig: router,
            )
          : MaterialApp(theme: TabbyTheme.lightTheme, home: launcher()),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> details(
  WidgetTester tester, {
  String amount = '150',
  String description = 'Loan',
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('create-tab-amount')),
    amount,
  );
  await tester.enterText(
    find.byKey(const ValueKey('create-tab-expense-title')),
    description,
  );
  await tap(tester, find.text('Full share'));
}

Future<void> addSave(WidgetTester tester) =>
    tap(tester, find.widgetWithText(TabbyButton, 'Add to Tab'));

Future<void> waitForRecorded(
  WidgetTester tester,
  bool Function() recorded,
) async {
  // A native platform/storage completion need not schedule a frame while it is
  // outstanding. pumpAndSettle alone does not establish save completion.
  for (var i = 0; i < 100 && !recorded(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
  expect(
    recorded(),
    isTrue,
    reason: 'The single Save tap must finish within 10 seconds.',
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => SupabaseConfig.debugUserIdOverride = null);
  for (final balance in [15000, -15000, 0]) {
    testWidgets(
      'existing ID selection shows direction $balance and Cancel writes nothing',
      (tester) async {
        final ledger = EntryLedger();
        ledger.state = ledger.state.copyWith(
          tabs: [
            ledger.state.tabs.single.copyWith(netBalanceCentavos: balance),
          ],
        );
        await mount(tester, ledger);
        await tap(
          tester,
          find.byKey(const ValueKey('create-tab-friend-friend-qa')),
        );
        expect(find.text('You already have a tab with Alex'), findsOneWidget);
        expect(
          find.textContaining(
            balance > 0
                ? 'Alex owes you'
                : balance < 0
                ? 'You owe Alex'
                : 'All settled',
          ),
          findsOneWidget,
        );
        await tap(tester, find.text('Cancel'));
        expect(ledger.state.tabs.single.entries, hasLength(1));
        expect(ledger.state.tabs.single.netBalanceCentavos, balance);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('create-tab-friend-friend-qa')),
              )
              .value,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'no existing relationship continues normal Create without a write',
    (tester) async {
      final ledger = EntryLedger(existing: false);
      await mount(tester, ledger);
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-qa')),
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tap(tester, find.text('Next'));
      expect(find.widgetWithText(TabbyButton, 'Create Tab'), findsOneWidget);
      expect(ledger.state.tabs, isEmpty);
    },
  );
  testWidgets(
    'lookup failure keeps selection uncommitted and retry checks again',
    (tester) async {
      final ledger = EntryLedger()..failLookup = true;
      await mount(tester, ledger);
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-qa')),
      );
      expect(
        find.textContaining('Could not check your shared tab'),
        findsOneWidget,
      );
      expect(ledger.state.tabs.single.entries, hasLength(1));
      ledger.failLookup = false;
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-qa')),
      );
      expect(find.text('You already have a tab with Alex'), findsOneWidget);
    },
  );
  testWidgets(
    'View Existing Tab opens exact history without financial writes',
    (tester) async {
      final ledger = EntryLedger();
      await mount(tester, ledger, routed: true);
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-qa')),
      );
      await tap(tester, find.text('View Existing Tab'));
      expect(find.text('History shared-tab'), findsOneWidget);
      expect(ledger.state.tabs.single.entries, hasLength(1));
    },
  );
  testWidgets(
    'Add existing warns, Review and Cancel preserve balance, Add Anyway saves once',
    (tester) async {
      final ledger = EntryLedger();
      await mount(tester, ledger);
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-qa')),
      );
      await tap(tester, find.text('Add New Expense'));
      expect(find.widgetWithText(TabbyButton, 'Add to Tab'), findsOneWidget);
      await details(tester);
      await addSave(tester);
      expect(find.text('Possible Duplicate Expense'), findsOneWidget);
      await tap(tester, find.text('Review Existing Expense'));
      expect(find.text('Existing Expense'), findsOneWidget);
      expect(ledger.state.tabs.single.netBalanceCentavos, 15000);
      await tap(tester, find.text('Back to Expense'));
      await addSave(tester);
      await tap(tester, find.text('Cancel'));
      expect(ledger.state.tabs.single.entries, hasLength(1));
      await addSave(tester);
      await tap(tester, find.text('Add Anyway'));
      expect(find.text('Expense recorded'), findsOneWidget);
      expect(ledger.state.tabs, hasLength(1));
      expect(ledger.state.tabs.single.id, 'shared-tab');
      expect(ledger.state.tabs.single.entries, hasLength(2));
      expect(ledger.state.tabs.single.netBalanceCentavos, 30000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'same amount with a different description saves without duplicate warning; rapid taps save once',
    (tester) async {
      final ledger = EntryLedger();
      await mount(tester, ledger, initial: 'shared-tab');
      await tap(tester, find.text('Next'));
      await details(tester, description: 'New loan');
      final button = find.widgetWithText(TabbyButton, 'Add to Tab');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Possible Duplicate Expense'), findsNothing);
      expect(ledger.state.tabs.single.entries, hasLength(2));
      expect(ledger.state.tabs.single.netBalanceCentavos, 30000);
    },
  );
  testWidgets(
    'custom group 0/150/300 persists exact draft and gives correct ledger balances',
    (tester) async {
      final ledger = EntryLedger(group: true, withExpense: false);
      await mount(tester, ledger, initial: 'shared-tab');
      await tap(tester, find.text('Next'));
      await tester.enterText(
        find.byKey(const ValueKey('create-tab-amount')),
        '450',
      );
      await tap(tester, find.text('Custom amounts'));
      for (final e in {
        me.id: '0',
        friend.id: '150',
        second.id: '300',
      }.entries) {
        await tester.enterText(
          find.byKey(ValueKey('custom-share-${e.key}')),
          e.value,
        );
      }
      await tester.pumpAndSettle();
      final draft = await const FormDraftStore().read(
        me.id,
        'expense:shared-tab',
      );
      expect(draft!['custom_amounts'], {
        me.id: '0',
        friend.id: '150',
        second.id: '300',
      });
      await addSave(tester);
      final tab = ledger.state.tabs.single;
      expect(
        tab.entries.single.participants.map((p) => p.shareAmountCentavos),
        [0, 15000, 30000],
      );
      expect(tab.netBalanceCentavos, 45000);
      expect(
        MockTabbyRepository.calculateNetBalance(tab.entries, friend.id),
        -15000,
      );
      expect(
        MockTabbyRepository.calculateNetBalance(tab.entries, second.id),
        -30000,
      );
      expect(find.text('Expense recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'custom over-allocation rejects save and keeps the editable draft',
    (tester) async {
      final ledger = EntryLedger(withExpense: false);
      await mount(tester, ledger, initial: 'shared-tab');
      await tap(tester, find.text('Next'));
      await tester.enterText(
        find.byKey(const ValueKey('create-tab-amount')),
        '150',
      );
      await tap(tester, find.text('Custom amounts'));
      await tester.enterText(
        find.byKey(ValueKey('custom-share-${me.id}')),
        '0',
      );
      await tester.enterText(
        find.byKey(ValueKey('custom-share-${friend.id}')),
        '151',
      );
      await addSave(tester);
      expect(find.textContaining('Their shares must add up'), findsOneWidget);
      expect(ledger.state.tabs.single.entries, isEmpty);
      await tester.enterText(
        find.byKey(ValueKey('custom-share-${friend.id}')),
        '150',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(ValueKey('custom-share-${friend.id}')),
            )
            .controller!
            .text,
        '150',
      );
      final correctedSave = tester.widget<TabbyButton>(
        find.widgetWithText(TabbyButton, 'Add to Tab'),
      );
      expect(correctedSave.onPressed, isNotNull);
      expect(correctedSave.isLoading, isFalse);
      await addSave(tester);
      await waitForRecorded(
        tester,
        () => ledger.state.tabs.single.entries.isNotEmpty,
      );
      expect(ledger.state.tabs.single.netBalanceCentavos, 15000);
    },
  );
  testWidgets(
    'response loss, Back and reopened draft retry original operation once',
    (tester) async {
      final ledger = ResponseLostLedger();
      await mount(tester, ledger, initial: 'shared-tab');
      await tap(tester, find.text('Next'));
      await details(tester, description: 'Second loan');
      await addSave(tester);
      expect(find.widgetWithText(TabbyButton, 'Retry Save'), findsOneWidget);
      expect(ledger.state.tabs.single.entries, hasLength(2));
      await tap(tester, find.byTooltip('Back'));
      expect(find.text('Keep this expense draft?'), findsOneWidget);
      await tap(tester, find.text('Keep draft'));
      await tap(tester, find.text('Open'));
      expect(find.byKey(const ValueKey('create-tab-details')), findsOneWidget);
      await tap(tester, find.widgetWithText(TabbyButton, 'Retry Save'));
      expect(ledger.operations, hasLength(2));
      expect(ledger.operations.toSet(), hasLength(1));
      expect(ledger.state.tabs.single.entries, hasLength(2));
      expect(ledger.state.tabs.single.netBalanceCentavos, 30000);
      expect(find.text('Expense recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'late lookup result cannot open a dialog after the form is removed',
    (tester) async {
      final ledger = EntryLedger()..lookup = Completer<BilateralTab?>();
      await mount(tester, ledger);
      await tester.tap(
        find.byKey(const ValueKey('create-tab-friend-friend-qa')),
      );
      await tester.pump();
      final tab = ledger.state.tabs.single;
      await tester.pumpWidget(const MaterialApp(home: Text('Account changed')));
      ledger.lookup!.complete(tab);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'account change dismisses both the existing-tab dialog and its form',
    (tester) async {
      final ledger = EntryLedger();
      await mount(tester, ledger);
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-qa')),
      );
      expect(find.text('You already have a tab with Alex'), findsOneWidget);
      SupabaseConfig.debugUserIdOverride = 'another-session';
      SupabaseConfig.sessionRevision.value++;
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AddExpenseModal), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new group records custom 0/150/300 without changing existing bilateral tabs',
    (tester) async {
      final ledger = EntryLedger(withExpense: false);
      ledger.state = ledger.state.copyWith(
        tabs: [
          ledger.state.tabs.single,
          ledger.state.tabs.single.copyWith(
            id: 'second-tab',
            counterpart: second,
          ),
        ],
      );
      await mount(tester, ledger);
      await tap(tester, find.text('Create a group tab'));
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-qa')),
      );
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-two')),
      );
      expect(find.textContaining('You already have a tab with'), findsNothing);
      await tap(tester, find.text('Next'));
      await tester.enterText(
        find.byKey(const ValueKey('create-tab-tab-name')),
        'Shared bill',
      );
      await tester.enterText(
        find.byKey(const ValueKey('create-tab-amount')),
        '450',
      );
      await tap(tester, find.text('Custom amounts'));
      for (final e in {
        me.id: '0',
        friend.id: '150',
        second.id: '300',
      }.entries) {
        await tester.enterText(
          find.byKey(ValueKey('custom-share-${e.key}')),
          e.value,
        );
      }
      await tap(tester, find.widgetWithText(TabbyButton, 'Create Tab'));
      final group = ledger.state.tabs.singleWhere((t) => t.isGroupTab);
      expect(
        group.entries.single.participants.map((p) => p.shareAmountCentavos),
        [0, 15000, 30000],
      );
      expect(group.netBalanceCentavos, 45000);
      expect(
        ledger.state.tabs
            .where((t) => !t.isGroupTab)
            .every((t) => t.entries.isEmpty),
        isTrue,
      );
      expect(find.text('Expense recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing the person in an existing Add form still checks their shared tab',
    (tester) async {
      final ledger = EntryLedger();
      ledger.state = ledger.state.copyWith(
        tabs: [
          ledger.state.tabs.single,
          ledger.state.tabs.single.copyWith(
            id: 'second-tab',
            counterpart: second,
          ),
        ],
      );
      await mount(tester, ledger, initial: 'shared-tab');
      await tap(
        tester,
        find.byKey(const ValueKey('create-tab-friend-friend-two')),
      );
      expect(find.text('You already have a tab with Alex'), findsOneWidget);
      expect(ledger.state.tabs.every((t) => t.entries.length == 1), isTrue);
      await tap(tester, find.text('Cancel'));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('create-tab-friend-friend-qa')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('create-tab-friend-friend-two')),
            )
            .value,
        isFalse,
      );
    },
  );
}
