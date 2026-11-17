import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/data/m2_command_queue.dart';
import 'package:tabby/features/tabs/data/m2_queries.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/presentation/contact_claim_screen.dart';

const owner = '00000000-0000-4000-8000-000000000001',
    peer = '00000000-0000-4000-8000-000000000002',
    claimId = '00000000-0000-4000-8000-000000000003';
final claim = {
  'id': claimId,
  'owner_id': owner,
  'target_id': peer,
  'status': 'pending',
  'snapshot': {'digest': 'fixture-digest', 'owner_net_centavos': 5001},
};
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'invitation requires exact account selection and explicit sharing consent; reopen retries same ID',
    (tester) async {
      final q = M2CommandQueue(
        actor: owner,
        current: () => true,
        wake: () async {},
      );
      final reads = M2Queries(
        actor: owner,
        current: () => true,
        rpc: (name, args) async => name == 'contact_claim_preview_v1'
            ? {
                'account_id': owner,
                'contact_id': 'contact',
                'source_tab_id': 'tab',
                'snapshot': claim['snapshot'],
              }
            : {
                'account_id': owner,
                'target': {
                  'id': peer,
                  'display_name': 'Exact fixture',
                  'friend_code': 'TAB-ABCDEF',
                },
              },
      );
      Widget screen() => MaterialApp(
        home: ContactClaimInvite(
          contactId: 'contact',
          tabId: 'tab',
          queue: q,
          queries: reads,
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send invitation'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'TAB-ABCDEF');
      await tester.tap(find.text('Find exact account'));
      await tester.pumpAndSettle();
      expect(find.text('Account ID: $peer'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send invitation'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
      expect(find.text('Saved on this device. Sync pending.'), findsOneWidget);
      final first = (await TabbyLocalCache.loadPendingOps(userId: owner))
          .single;
      expect(first['m2_command']['target_id'], peer);
      expect(first['m2_command']['snapshot_digest'], 'fixture-digest');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry saved invitation'));
      await tester.pumpAndSettle();
      expect(
        (await TabbyLocalCache.loadPendingOps(userId: owner))
            .single['operation_id'],
        first['operation_id'],
      );
    },
  );
  testWidgets(
    'recipient accept is disabled until consent; decline freezes an explicit false decision',
    (tester) async {
      final q = M2CommandQueue(
            actor: peer,
            current: () => true,
            wake: () async {},
          ),
          reads = M2Queries(
            actor: peer,
            current: () => true,
            rpc: (_, __) async => {},
          );
      await tester.pumpWidget(
        MaterialApp(
          home: ContactClaimDecision(claim: claim, queue: q, queries: reads),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Accept claim'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      final op = (await TabbyLocalCache.loadPendingOps(userId: peer)).single;
      expect(op['m2_command']['accept'], false);
      expect(op['m2_command']['claim_id'], claimId);
      expect(find.text('Saved by the server.'), findsNothing);
    },
  );
  testWidgets(
    'owner cannot decide their own invitation and expired account renders no old history',
    (tester) async {
      var current = true;
      final q = M2CommandQueue(
            actor: owner,
            current: () => current,
            wake: () async {},
          ),
          reads = M2Queries(
            actor: owner,
            current: () => current,
            rpc: (_, __) async => {},
          );
      await tester.pumpWidget(
        MaterialApp(
          home: ContactClaimDecision(claim: claim, queue: q, queries: reads),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Accept claim'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      current = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ContactClaimDecision(
            key: const ValueKey('expired'),
            claim: claim,
            queue: q,
            queries: reads,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review contact claim'), findsNothing);
    },
  );
}
