import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/application/tabby_state.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  group('Shareable Tabby ID', () {
    test('normalizes a copied ID to the canonical uppercase format', () {
      expect(normalizeFriendCode('  tab-7k4p2m  '), 'TAB-7K4P2M');
    });

    test('rejects an ID with the wrong length or characters', () {
      expect(normalizeFriendCode('TAB-123'), isNull);
      expect(normalizeFriendCode('TAB-7K4P2!'), isNull);
    });

    test('keeps the shareable ID through user serialization', () {
      const user = TabbyUser(
        id: 'user-1',
        displayName: 'Alex',
        email: 'alex@example.com',
        phone: '',
        friendCode: 'TAB-7K4P2M',
      );

      final restored = TabbyUser.fromMap(user.toMap());

      expect(restored.friendCode, 'TAB-7K4P2M');
    });
  });

  group('FriendRequest', () {
    test('parses an incoming request and exposes only relationship metadata', () {
      final request = FriendRequest.fromMap(const {
        'id': 'request-1',
        'requester_id': 'user-alex',
        'addressee_id': 'user-me',
        'status': 'pending',
        'created_at': '2026-09-17T01:02:03.000Z',
        'responded_at': null,
        'requester': {
          'id': 'user-alex',
          'display_name': 'Alex',
          'avatar_url': null,
          'friend_code': 'TAB-7K4P2M',
        },
        'addressee': {
          'id': 'user-me',
          'display_name': 'Frienzal',
          'avatar_url': null,
          'friend_code': 'TAB-9N6R3Q',
        },
      }, currentUserId: 'user-me');

      expect(request.id, 'request-1');
      expect(request.status, FriendRequestStatus.pending);
      expect(request.isIncoming, isTrue);
      expect(request.otherUser.displayName, 'Alex');
      expect(request.otherUser.email, isEmpty);
      expect(request.otherUser.phone, isEmpty);
    });

    test('maps an accepted request without treating it as incoming', () {
      final request = FriendRequest.fromMap(const {
        'id': 'request-2',
        'requester_id': 'user-me',
        'addressee_id': 'user-alex',
        'status': 'accepted',
        'created_at': '2026-09-17T01:02:03.000Z',
        'responded_at': '2026-09-17T01:03:03.000Z',
        'requester': {
          'id': 'user-me',
          'display_name': 'Frienzal',
          'avatar_url': null,
          'friend_code': 'TAB-9N6R3Q',
        },
        'addressee': {
          'id': 'user-alex',
          'display_name': 'Alex',
          'avatar_url': null,
          'friend_code': 'TAB-7K4P2M',
        },
      });

      expect(request.status, FriendRequestStatus.accepted);
      expect(request.isIncoming, isFalse);
      expect(request.otherUser.displayName, 'Alex');
    });
  });

  group('Friend request RPC response mapping', () {
    test('maps the sanitized RPC row without private profile fields', () {
      final request = SupabaseTabbyRepository.parseFriendRequestRow(const {
        'id': 'request-3',
        'requester_id': 'user-alex',
        'addressee_id': 'user-me',
        'status': 'pending',
        'created_at': '2026-09-17T01:02:03.000Z',
        'responded_at': null,
        'requester_display_name': 'Alex',
        'requester_avatar_url': null,
        'requester_friend_code': 'TAB-7K4P2M',
        'addressee_display_name': 'Frienzal',
        'addressee_avatar_url': null,
        'addressee_friend_code': 'TAB-9N6R3Q',
      }, currentUserId: 'user-me');

      expect(request.otherUser.id, 'user-alex');
      expect(request.otherUser.email, isEmpty);
      expect(request.otherUser.phone, isEmpty);
      expect(request.otherUser.gcashNumber, isEmpty);
      expect(request.otherUser.mayaNumber, isEmpty);
    });
  });

  group('Friend request repository boundary', () {
    test('does not fabricate friend data while Supabase is offline', () async {
      final repository = SupabaseTabbyRepository.instance;

      expect(repository.isConnected, isFalse);
      expect(await repository.findUserByFriendCode('TAB-7K4P2M'), isNull);
      expect(
        await repository.sendFriendRequest(friendCode: 'TAB-7K4P2M'),
        isNull,
      );
      expect(await repository.fetchFriendRequests('user-me'), isEmpty);
      expect(
        await repository.respondToFriendRequest(
          friendshipId: 'request-1',
          accept: true,
        ),
        isNull,
      );
    });
  });

  test('dashboard state preserves friend requests across a state copy', () {
    final request = FriendRequest(
      id: 'request-4',
      requesterId: 'user-alex',
      addresseeId: 'user-me',
      requester: const TabbyUser(
        id: 'user-alex',
        displayName: 'Alex',
        email: '',
        phone: '',
        friendCode: 'TAB-7K4P2M',
      ),
      addressee: const TabbyUser(
        id: 'user-me',
        displayName: 'Frienzal',
        email: '',
        phone: '',
        friendCode: 'TAB-9N6R3Q',
      ),
      status: FriendRequestStatus.pending,
      createdAt: DateTime(2026, 9, 17),
      currentUserId: 'user-me',
    );

    final state = TabbyDashboardState(
      tabs: const [],
      activities: const [],
      reminders: const [],
      friendRequests: [request],
    );

    expect(state.copyWith().friendRequests, hasLength(1));
    expect(state.copyWith().friendRequests.single.id, 'request-4');
  });
}
