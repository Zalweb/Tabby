import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/profile/application/privacy_export.dart';
import 'package:tabby/features/profile/presentation/privacy_controls_screen.dart';

const one = '00000000-0000-4000-8000-000000000001';
const two = '00000000-0000-4000-8000-000000000002';

Map<String, dynamic> page({
  String account = 'a',
  String section = 'expenses',
  List<Map<String, dynamic>>? records,
  String? next,
}) => {
  'version': 1,
  'account_id': account,
  'section': section,
  'records':
      records ??
      [
        {'id': one, 'description': 'Fixture expense'},
      ],
  'next_cursor': next,
};

PrivacyExport exporter({
  Future<dynamic> Function(String, String?)? read,
  Future<dynamic> Function()? status,
  bool Function()? current,
}) => PrivacyExport(
  accountId: () => 'a',
  captureCurrent: () => current ?? () => true,
  fetch: () async => null,
  fetchLedgerPage: read,
  fetchDeletionStatus: status,
);

void main() {
  for (final section in [
    'receiving_methods',
    'connections',
    'contacts',
    'notifications',
    'reminders',
  ]) {
    test(
      'private $section page retains caller and section validation',
      () async {
        final service = exporter(
          read: (requested, after) async => page(section: requested),
        );
        expect((await service.ledgerPage(section))['section'], section);
        await expectLater(
          exporter(
            read: (_, __) async => page(account: 'b', section: section),
          ).ledgerPage(section),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'pending status reads reject a same-account session replacement',
    () async {
      var current = true;
      final result = Completer<dynamic>();
      final service = exporter(
        current: () => current,
        status: () => result.future,
      );
      final pending = service.deletionStatus();
      current = false;
      result.complete({
        'account_id': 'a',
        'id': 'request',
        'status': 'requested',
      });
      await expectLater(pending, throwsStateError);
    },
  );

  test(
    'ledger copy retains section/cursor and accepts empty final pages',
    () async {
      final calls = <String?>[];
      final service = exporter(
        read: (section, after) async {
          calls.add(after);
          return after == null ? page(next: one) : page(records: []);
        },
      );
      expect((await service.ledgerPage('expenses'))['next_cursor'], one);
      expect(
        (await service.ledgerPage('expenses', after: one))['records'],
        isEmpty,
      );
      expect(calls, [null, one]);
    },
  );

  test(
    'wrong account, section, order, duplicate IDs, size and cursor fail closed',
    () async {
      for (final invalid in [
        page(account: 'b'),
        page(section: 'payments'),
        page(
          records: [
            {'id': two},
            {'id': one},
          ],
        ),
        page(
          records: [
            {'id': one},
            {'id': one},
          ],
        ),
        page(next: two),
        page(records: [], next: one),
        page(
          records: [
            {'id': 'bad'},
          ],
        ),
        page(records: List.generate(51, (_) => {'id': one})),
      ]) {
        await expectLater(
          exporter(read: (_, __) async => invalid).ledgerPage('expenses'),
          throwsFormatException,
        );
      }
      await expectLater(
        exporter(read: (_, __) async => page())
            .ledgerPage('expenses', after: one),
        throwsFormatException,
      );
    },
  );

  test(
    'late ledger pages and same-account new sessions never escape',
    () async {
      var current = true;
      final result = Completer<dynamic>();
      final service = exporter(
        read: (_, __) => result.future,
        current: () => current,
      );
      final loading = service.ledgerPage('expenses');
      await expectLater(service.ledgerPage('expenses'), throwsStateError);
      current = false;
      result.complete(page());
      await expectLater(loading, throwsStateError);
    },
  );

  test('status read returns no request or validated current status and rejects foreign results', () async {
    expect(await exporter(status: () async => null).deletionStatus(), null);
    for (final status in ['requested', 'processing', 'completed']) {
      expect(
        (await exporter(
          status: () async => {
            'id': 'request',
            'account_id': 'a',
            'status': status,
          },
        ).deletionStatus())!['status'],
        status,
      );
    }
    await expectLater(
      exporter(
        status: () async => {
          'id': 'request',
          'account_id': 'b',
          'status': 'requested',
        },
      ).deletionStatus(),
      throwsFormatException,
    );
  });

  testWidgets(
    'history next page retries the same cursor after a failed request',
    (tester) async {
      final calls = <String?>[];
      var failed = false;
      final service = exporter(
        read: (_, after) async {
          calls.add(after);
          if (after == one && !failed) {
            failed = true;
            throw StateError('network');
          }
          return after == null
              ? page(next: one)
              : page(
                  records: [
                    {'id': two},
                  ],
                );
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: PrivacyControlsScreen(exporter: service)),
      );
      await tester.scrollUntilVisible(
        find.text('Prepare first history page'),
        300,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare first history page'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Next history page'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next history page'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not prepare this page. Please try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Next history page'));
      await tester.pumpAndSettle();
      expect(calls, [null, one, one]);
      expect(find.text('End of this history section.'), findsOneWidget);
    },
  );

  testWidgets(
    'reopened privacy screen checks existing request without submitting another',
    (tester) async {
      var current = true;
      var reads = 0;
      final service = exporter(
        current: () => current,
        status: () async {
          reads++;
          return {
            'id': 'existing-request',
            'account_id': 'a',
            'status': 'processing',
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: PrivacyControlsScreen(exporter: service)),
      );
      await tester.scrollUntilVisible(
        find.text('Check deletion request status'),
        400,
      );
      await tester.tap(find.text('Check deletion request status'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(SelectableText),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Status: processing.'), findsOneWidget);
      expect(reads, 1);
      current = false;
      SupabaseConfig.sessionRevision.value++;
      await tester.pump();
      expect(find.byType(SelectableText), findsNothing);
    },
  );
}
