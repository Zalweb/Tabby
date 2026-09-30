import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  group('Realtime Friend Request & Notification Tests', () {
    test('FriendRequest.copyWith preserves fields and updates status', () {
      final now = DateTime.now();
      const userA = TabbyUser(id: 'user_a', displayName: 'Alice', email: 'alice@tabby.ph', phone: '09171234567');
      const userB = TabbyUser(id: 'user_b', displayName: 'Bob', email: 'bob@tabby.ph', phone: '09181234567');

      final req = FriendRequest(
        id: 'fr_1',
        requesterId: 'user_a',
        addresseeId: 'user_b',
        requester: userA,
        addressee: userB,
        status: FriendRequestStatus.pending,
        createdAt: now,
        currentUserId: 'user_b',
      );

      expect(req.isIncoming, isTrue);
      expect(req.otherUser.id, 'user_a');
      expect(req.status, FriendRequestStatus.pending);

      final accepted = req.copyWith(
        status: FriendRequestStatus.accepted,
        respondedAt: now,
      );

      expect(accepted.id, 'fr_1');
      expect(accepted.status, FriendRequestStatus.accepted);
      expect(accepted.respondedAt, now);
      expect(accepted.otherUser.displayName, 'Alice');
    });

    test('acceptedFriendUserIds recognizes accepted friend request without app reload', () {
      const userA = TabbyUser(id: 'user_a', displayName: 'Alice', email: 'alice@tabby.ph', phone: '09171234567', friendCode: 'TAB-ABC123');
      const userB = TabbyUser(id: 'user_b', displayName: 'Bob', email: 'bob@tabby.ph', phone: '09181234567');

      final req = FriendRequest(
        id: 'fr_1',
        requesterId: 'user_a',
        addresseeId: 'user_b',
        requester: userA,
        addressee: userB,
        status: FriendRequestStatus.accepted,
        createdAt: DateTime.now(),
        currentUserId: 'user_b',
      );

      final eligibleIds = acceptedFriendUserIds([req]);
      expect(eligibleIds.contains('user_a'), isTrue);
    });

    test('AppNotification handles friend_request type', () {
      final notif = AppNotification(
        id: 'notif_1',
        recipientUserId: 'user_b',
        type: 'friend_request',
        title: 'New Friend Request',
        body: 'Alice sent you a friend request.',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(notif.type, 'friend_request');
      expect(notif.title, 'New Friend Request');
      expect(notif.isRead, isFalse);
    });
  });
}
