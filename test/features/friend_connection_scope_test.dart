import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const owner = TabbyUser(
  id: 'account-a',
  displayName: 'Synthetic owner',
  email: '',
  phone: '',
);
const target = TabbyUser(
  id: 'friend',
  displayName: 'Synthetic friend',
  email: '',
  phone: '',
  friendCode: 'TAB-7K4P2M',
);
FriendRequest pendingRequest() => FriendRequest(
  id: 'synthetic-request',
  requesterId: owner.id,
  addresseeId: target.id,
  requester: owner,
  addressee: target,
  status: FriendRequestStatus.pending,
  createdAt: DateTime(2026),
  currentUserId: owner.id,
);

void main() {
  setUp(() {
    SupabaseConfig.debugUserIdOverride = owner.id;
    SupabaseConfig.captureSession();
  });
  tearDown(() => SupabaseConfig.debugUserIdOverride = null);
  for (final phase in ['lookup', 'found', 'send']) {
    for (final same in [false, true]) {
      testWidgets(
        'connect sheet drops $phase on ${same ? 'same-account relogin' : 'account change'}',
        (tester) async {
          final lookup = Completer<TabbyUser?>(),
              send = Completer<FriendRequest?>();
          if (phase != 'lookup') lookup.complete(target);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ConnectByIdSheet(
                        findFriend: (_) => lookup.future,
                        sendFriendRequest: (_) => send.future,
                      ),
                    ),
                    child: const Text('Open connect'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open connect'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'TAB-7K4P2M');
          await tester.tap(find.byIcon(Icons.search_rounded));
          await tester.pump();
          if (phase != 'lookup') {
            await tester.pumpAndSettle();
            expect(find.text('Synthetic friend'), findsOneWidget);
          }
          if (phase == 'send') {
            await tester.tap(find.text('Send Friend Request'));
            await tester.pump();
          }
          SupabaseConfig.debugUserIdOverride = 'account-b';
          SupabaseConfig.captureSession();
          if (same) {
            SupabaseConfig.debugUserIdOverride = owner.id;
            SupabaseConfig.captureSession();
          }
          SupabaseConfig.sessionRevision.value++;
          if (!lookup.isCompleted) lookup.complete(target);
          send.complete(pendingRequest());
          await tester.pumpAndSettle();
          expect(find.text('Connect with a Friend'), findsNothing);
          expect(
            find.text('Request sent. They can accept it from their Profile.'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'editing an ID clears the previously matched person before sending',
    (tester) async {
      var sent = 0;
      await _open(
        tester,
        lookup: (_) async => target,
        send: (_) async {
          sent++;
          return pendingRequest();
        },
      );
      await tester.enterText(find.byType(TextField), 'TAB-7K4P2M');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic friend'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'TAB-9N6R3Q');
      await tester.pumpAndSettle();
      expect(find.text('Synthetic friend'), findsNothing);
      expect(find.text('Send Friend Request'), findsNothing);
      expect(sent, 0);
    },
  );
  testWidgets(
    'normal request submission freezes its looked-up ID while sending',
    (tester) async {
      final reply = Completer<FriendRequest?>();
      String? sentCode;
      await _open(
        tester,
        lookup: (_) async => target,
        send: (value) {
          sentCode = value;
          return reply.future;
        },
      );
      await tester.enterText(find.byType(TextField), 'TAB-7K4P2M');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Friend Request'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(sentCode, 'TAB-7K4P2M');
      reply.complete(pendingRequest());
      await tester.pumpAndSettle();
      expect(
        find.text('Request sent. They can accept it from their Profile.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'editing an ID discards a pending lookup for the earlier person',
    (tester) async {
      final result = Completer<TabbyUser?>();
      await _open(
        tester,
        lookup: (_) => result.future,
        send: (_) async => null,
      );
      await tester.enterText(find.byType(TextField), 'TAB-7K4P2M');
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'TAB-9N6R3Q');
      result.complete(target);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic friend'), findsNothing);
      expect(find.text('Send Friend Request'), findsNothing);
    },
  );
}

Future<void> _open(
  WidgetTester tester, {
  required FriendLookup lookup,
  required FriendRequestSubmitter send,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) =>
                  ConnectByIdSheet(findFriend: lookup, sendFriendRequest: send),
            ),
            child: const Text('Open connect'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open connect'));
  await tester.pumpAndSettle();
}
