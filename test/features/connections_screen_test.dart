import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';

import 'package:tabby/features/connections/presentation/connections_screen.dart';

void main() {
  testWidgets('Connections keeps the emerald header and friend controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ConnectionsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Add Friend'), findsOneWidget);
  });
  testWidgets('accept and decline share one in-flight action per request', (
    tester,
  ) async {
    final notifier = _RequestNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tabbyProvider.overrideWith((_) => notifier)],
        child: const MaterialApp(home: ConnectionsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Requests (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Accept request'));
    await tester.tap(find.byTooltip('Decline request'));
    await tester.pump();
    final acceptDisabled =
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Accept request',
              ),
            )
            .onPressed ==
        null;
    final declineDisabled =
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Decline request',
              ),
            )
            .onPressed ==
        null;
    notifier.reply.complete(true);
    await tester.pumpAndSettle();
    expect(notifier.calls, 1);
    expect(acceptDisabled && declineDisabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _RequestNotifier extends TabbyNotifier {
  _RequestNotifier() : super(loadInitialData: false) {
    state = state.copyWith(
      friendRequests: [
        FriendRequest(
          id: 'request',
          requesterId: 'friend',
          addresseeId: 'user-me',
          requester: const TabbyUser(
            id: 'friend',
            displayName: 'Synthetic friend',
            email: '',
            phone: '',
          ),
          addressee: const TabbyUser(
            id: 'user-me',
            displayName: 'Synthetic owner',
            email: '',
            phone: '',
          ),
          status: FriendRequestStatus.pending,
          createdAt: DateTime(2026),
          currentUserId: 'user-me',
        ),
      ],
    );
  }
  final reply = Completer<bool>();
  int calls = 0;
  @override
  Future<bool> respondToFriendRequest({
    required String friendshipId,
    required bool accept,
  }) {
    calls++;
    return reply.future;
  }
}
