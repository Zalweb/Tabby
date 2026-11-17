import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/profile/application/privacy_export.dart';
import 'package:tabby/features/profile/presentation/privacy_controls_screen.dart';

void main() {
  test(
      'deletion requires a matching server acknowledgment and rejects late sessions',
      () async {
    var current = true;
    final pending = Completer<dynamic>();
    final service = PrivacyExport(
        accountId: () => 'a',
        captureCurrent: () => () => current,
        fetch: () async => null,
        requestDeletion: () => pending.future);
    final result = service.submitDeletionRequest();
    current = false;
    pending
        .complete({'account_id': 'a', 'id': 'request', 'status': 'requested'});
    await expectLater(result, throwsStateError);
    await expectLater(
        PrivacyExport(
            accountId: () => 'a',
            captureCurrent: () => () => true,
            fetch: () async => null,
            requestDeletion: () async => {
                  'account_id': 'b',
                  'id': 'request',
                  'status': 'requested'
                }).submitDeletionRequest(),
        throwsFormatException);
  });

  testWidgets(
      'deletion request needs confirmation and shows only server acknowledgment',
      (tester) async {
    var calls = 0;
    final service = PrivacyExport(
        accountId: () => 'a',
        captureCurrent: () => () => true,
        fetch: () async => null,
        requestDeletion: () async {
          calls++;
          return {
            'account_id': 'a',
            'id': 'request-fixture',
            'status': 'requested'
          };
        });
    await tester.pumpWidget(
        MaterialApp(home: PrivacyControlsScreen(exporter: service)));
    await tester.scrollUntilVisible(find.text('Request account deletion'), 300);
    await tester.tap(find.text('Request account deletion'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Keep account'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Request account deletion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('Your account has not been deleted.'),
        findsOneWidget);
  });

  Map<String, dynamic> snapshot([String account = 'a']) => {
        'account_id': account,
        'version': 1,
        'scope': 'profile_and_owned_contacts',
        'profile': {'display_name': 'Private fixture'},
        'contacts': [],
      };

  test('export requires authentication and server acknowledgment', () async {
    var called = false;
    final service = PrivacyExport(
      accountId: () => null,
      captureCurrent: () => () => true,
      fetch: () async {
        called = true;
        return snapshot();
      },
    );
    await expectLater(service.load(), throwsStateError);
    expect(called, isFalse);
  });

  test('foreign, obsolete and malformed exports are rejected', () async {
    var current = true;
    final response = Completer<dynamic>();
    final service = PrivacyExport(
      accountId: () => 'a',
      captureCurrent: () => () => current,
      fetch: () => response.future,
    );
    final pending = service.load();
    await expectLater(service.load(), throwsStateError);
    current = false;
    response.complete(snapshot());
    await expectLater(pending, throwsStateError);
    for (final invalid in [snapshot('b'), <String, dynamic>{}, null]) {
      await expectLater(
          PrivacyExport(
              accountId: () => 'a',
              captureCurrent: () => () => true,
              fetch: () async => invalid).load(),
          throwsFormatException);
    }
  });

  test('failure releases the busy guard for explicit retry', () async {
    var attempts = 0;
    final service = PrivacyExport(
        accountId: () => 'a',
        captureCurrent: () => () => true,
        fetch: () async {
          if (++attempts == 1) throw StateError('network');
          return snapshot();
        });
    await expectLater(service.load(), throwsStateError);
    expect(jsonDecode(await service.load())['account_id'], 'a');
  });

  testWidgets(
      'notice explains scope and clears displayed data on session change',
      (tester) async {
    var current = true;
    final service = PrivacyExport(
        accountId: () => 'a',
        captureCurrent: () => () => current,
        fetch: () async => snapshot());
    await tester.pumpWidget(
        MaterialApp(home: PrivacyControlsScreen(exporter: service)));
    expect(find.textContaining('This limited copy excludes'), findsOneWidget);
    await tester.ensureVisible(find.text('Prepare profile copy'));
    await tester.tap(find.text('Prepare profile copy'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    current = false;
    SupabaseConfig.sessionRevision.value++;
    await tester.pump();
    expect(find.byType(SelectableText), findsNothing);
    expect(find.textContaining('The account changed.'), findsOneWidget);
  });
}
