import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/expense_changes.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/due_reminders.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/expense_change_screen.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

Map<String, dynamic> revision(String role) => {
      'change_id': 'change',
      'original_id': 'z-original',
      'role': role,
      'kind': 'correct',
      'reason': 'Agreed higher total'
    };
Map<String, dynamic> row() {
  Map<String, dynamic> transaction(String id, String title, int total,
          String payer, int own, int other, String role) =>
      {
        'id': id,
        'description': title,
        'total_amount_centavos': total,
        'category': 'food',
        'status': 'acknowledged',
        'created_at': '2026-11-02T00:00:00Z',
        'due_date': '2026-12-01',
        'expense_revision': revision(role),
        'transaction_participants': [
          for (final who in ['user-me', 'friend'])
            {
              'user_id': who,
              'participant_role': who == payer ? 'payer' : 'debtor',
              'share_amount_centavos': who == 'user-me' ? own : other
            }
        ],
      };
  return {
    'id': 'tab',
    'tab_type': 'individual',
    'user_a': 'user-me',
    'user_b': 'friend',
    'tab_members': [
      for (final who in ['user-me', 'friend'])
        {
          'user_id': who,
          'users': {'id': who, 'display_name': who}
        }
    ],
    'transactions': [
      transaction('z-original', 'Original dinner', 10001, 'user-me', 5000, 5001,
          'original'),
      transaction(
          'reverse', 'Reversal dinner', 5001, 'friend', 5001, 0, 'reversal'),
      transaction('a-replacement', 'Replacement dinner', 15001, 'user-me', 7500,
          7501, 'replacement')
    ],
    'payments': <dynamic>[]
  };
}

class _Notifier extends TabbyNotifier {
  _Notifier(BilateralTab tab) : super(loadInitialData: false) {
    state = state.copyWith(tabs: [tab]);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'upward correction schedules one replacement despite equal due dates and adversarial IDs',
      () {
    final tab = SupabaseTabbyRepository.parseTabRow(row(), 'user-me',
        netBalance: 7501)!;
    final cached = BilateralTab.fromMap(
        jsonDecode(jsonEncode(tab.toMap())) as Map<String, dynamic>);
    expect(MockTabbyRepository.calculateNetBalance(cached.entries, 'user-me'),
        7501);
    final reminders = deriveDueReminders([cached], 'user-me');
    expect(reminders, hasLength(1));
    expect(reminders.single.id, endsWith('a-replacement'));
    expect(reminders.single.amountCentavos, 7501);
    expect(cached.entries.first.revision!.reason, 'Agreed higher total');
    expect(cached.entries.last.participants, hasLength(2));
  });
  test(
      'revision parent provenance survives cache and malformed metadata fails closed',
      () {
    final source =
        SupabaseTabbyRepository.parseTabRow(row(), 'user-me')!.entries.first;
    final ref = ExpenseRevision.fromMap({
      ...revision('original'),
      'parent_change_id': 'earlier-change',
      'parent_original_id': 'earlier-original'
    });
    final copy = LedgerEntry.fromMap(source.copyWith(revision: ref).toMap());
    expect(copy.revision!.parentOriginalId, 'earlier-original');
    expect(copy.revision!.parentChangeId, 'earlier-change');
    expect(
        () => ExpenseRevision.fromMap(
            {...revision('original'), 'role': 'unknown'}),
        throwsFormatException);
    final old = source.toMap()..remove('revision');
    expect(LedgerEntry.fromMap(old).revision, isNull);
  });
  testWidgets(
      'actual parsed bilateral detail exposes correction action and cached audit reason',
      (tester) async {
    final tab = SupabaseTabbyRepository.parseTabRow(row(), 'user-me',
        netBalance: 7501)!;
    await tester.pumpWidget(ProviderScope(
        overrides: [tabbyProvider.overrideWith((ref) => _Notifier(tab))],
        child: const MaterialApp(home: TabDetailScreen(tabId: 'tab'))));
    await tester.pumpAndSettle();
    expect(find.text('Revised original'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Replacement dinner'), 200,
        scrollable: find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
    await tester.tap(find.text('Replacement dinner'));
    await tester.pumpAndSettle();
    expect(find.text('Expense changes'), findsOneWidget);
    expect(find.text('Change reason: Agreed higher total'), findsOneWidget);
  });
  testWidgets(
      'all required group reviewers receive an action, beyond legacy first reviewer',
      (tester) async {
    final entry =
        SupabaseTabbyRepository.parseTabRow(row(), 'user-me')!.entries.last;
    final service = ExpenseChanges(
        owner: 'third-reviewer',
        current: () => true,
        rpc: (name, params) async => {
              'account_id': 'third-reviewer',
              'transaction_id': entry.id,
              'can_request': false,
              'changes': [
                {
                  'id': 'change',
                  'transaction_id': entry.id,
                  'kind': 'correct',
                  'reason': 'Agreed total',
                  'new_total_centavos': 7001,
                  'requested_by': 'requester',
                  'reviewer_id': 'first-reviewer',
                  'can_review': true,
                  'required_reviewers': 2,
                  'accepted_reviewers': 1,
                  'status': 'pending'
                }
              ]
            });
    await tester.pumpWidget(MaterialApp(
        home: ExpenseChangeScreen(
            entry: entry, service: service, refreshHistory: () async => true)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Review and accept'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Approvals: 1 of 2'), findsOneWidget);
    expect(find.text('Review and accept'), findsOneWidget);
  });
  testWidgets(
      'manual contact writes require explicit outside-app agreement and refresh only after acknowledgment',
      (tester) async {
    final entry =
        SupabaseTabbyRepository.parseTabRow(row(), 'user-me')!.entries.last;
    var writes = 0, refreshes = 0, applied = false;
    final service = ExpenseChanges(
        owner: 'owner',
        current: () => true,
        rpc: (name, params) async {
          if (name == 'request_expense_change_v2') {
            writes++;
            expect(params['p_contact_agreement'], isTrue);
            expect(params['p_expected_actor'], 'owner');
            applied = true;
            return 'change';
          }
          return {
            'account_id': 'owner',
            'transaction_id': entry.id,
            'manual_contact': true,
            'can_request': !applied,
            'changes': applied
                ? [
                    {
                      'id': 'change',
                      'transaction_id': entry.id,
                      'kind': 'correct',
                      'reason': 'Agreed total',
                      'new_total_centavos': 7001,
                      'requested_by': 'owner',
                      'reviewer_id': null,
                      'status': 'applied',
                      'required_reviewers': 0,
                      'accepted_reviewers': 0,
                      'manual_contact_agreement': true
                    }
                  ]
                : []
          };
        });
    await tester.pumpWidget(MaterialApp(
        home: ExpenseChangeScreen(
            entry: entry,
            service: service,
            refreshHistory: () async {
              refreshes++;
              return true;
            })));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reason'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField).first, '70.01');
    await tester.enterText(find.byType(TextField).last, 'Agreed total');
    await tester.ensureVisible(find.text('Record agreed change'));
    await tester.tap(find.text('Record agreed change'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Record agreed change'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(refreshes, 1);
    expect(
        find.textContaining('Outside-app agreement recorded'), findsOneWidget);
  });
}
