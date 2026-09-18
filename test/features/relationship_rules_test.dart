import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/main.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepted friends remain visible even without an active tab', () {
    const friend = TabbyUser(
      id: 'friend-alex',
      displayName: 'Alex',
      email: 'alex@example.com',
      phone: '+639171112233',
      friendCode: 'TAB-7K4P2M',
    );
    final request = FriendRequest(
      id: 'friendship-alex',
      requesterId: 'user-me',
      addresseeId: friend.id,
      requester: MockUserFixtures.current,
      addressee: friend,
      status: FriendRequestStatus.accepted,
      createdAt: DateTime(2026, 9, 17),
      currentUserId: MockUserFixtures.current.id,
    );
    final notifier = TabbyNotifier();
    notifier.state = notifier.state.copyWith(
      tabs: const [],
      friendRequests: [request],
    );
    final container = ProviderContainer(
      overrides: [tabbyProvider.overrideWith((_) => notifier)],
    );
    addTearDown(container.dispose);

    expect(container.read(friendsProvider).map((user) => user.id), [friend.id]);
  });

  test('unregistered tab participants are excluded from Friends', () {
    const unregistered = TabbyUser(
      id: 'contact-mark',
      displayName: 'Mark',
      email: '',
      phone: '+639171112233',
    );
    final notifier = TabbyNotifier();
    notifier.state = notifier.state.copyWith(
      tabs: [
        BilateralTab(
          id: 'tab-mark',
          counterpart: unregistered,
          netBalanceCentavos: 35000,
          itemCount: 1,
          entries: const [],
          lastUpdated: DateTime(2026, 9, 17),
          isTabOnlyParticipant: true,
        ),
      ],
      friendRequests: const [],
    );
    final container = ProviderContainer(
      overrides: [tabbyProvider.overrideWith((_) => notifier)],
    );
    addTearDown(container.dispose);

    expect(container.read(friendsProvider), isEmpty);
  });

  test('new unregistered expenses create tab-only participants', () async {
    final notifier = TabbyNotifier();
    notifier.state = notifier.state.copyWith(tabs: const []);
    addTearDown(notifier.dispose);

    await notifier.addExpense(
      counterpartId: 'user-mark',
      counterpartName: 'Mark',
      title: 'Lunch',
      totalAmountCentavos: 35000,
      category: ExpenseCategory.food,
      paidByMe: true,
      isEqualSplit: false,
      isConnectedFriend: false,
    );

    expect(notifier.state.tabs.single.toMap()['isTabOnlyParticipant'], isTrue);
  });

  test('Supabase contact members deserialize as tab-only participants', () {
    final tab = SupabaseTabbyRepository.parseTabRow(
      {
        'id': 'tab-contact-mark',
        'tab_type': 'individual',
        'tab_members': [
          {
            'user_id': 'user-me',
            'users': {'display_name': 'Frienzal'},
          },
          {
            'contact_id': 'contact-mark',
            'contacts': {
              'display_name': 'Mark',
              'phone': '+639171112233',
            },
          },
        ],
      },
      'user-me',
      netBalance: 35000,
    );

    expect(tab, isNotNull);
    expect(tab!.isTabOnlyParticipant, isTrue);
  });

  test('group membership keeps only accepted friend user IDs', () {
    final accepted = _friendRequest(
      id: 'friendship-accepted',
      friendId: 'friend-alex',
      status: FriendRequestStatus.accepted,
    );
    final pending = _friendRequest(
      id: 'friendship-pending',
      friendId: 'friend-pat',
      status: FriendRequestStatus.pending,
    );

    expect(
      filterEligibleGroupMemberIds(
        requestedIds: const ['friend-alex', 'friend-pat', 'random-user'],
        friendRequests: [accepted, pending],
      ),
      ['friend-alex'],
    );
  });

  testWidgets('group creation does not offer unregistered member input',
      (tester) async {
    AppState.isAuthenticated.value = true;
    AppState.hasSeenOnboarding.value = true;
    appRouter.go('/profile');

    await tester.pumpWidget(const ProviderScope(child: TabbyApp()));
    await tester.pumpAndSettle();

    final createGroup = find.text('Create a Group').first;
    await tester.ensureVisible(createGroup);
    await tester.tap(createGroup);
    await tester.pumpAndSettle();

    expect(find.text('Create New Group Tab'), findsOneWidget);
    expect(find.text('Select Members from Friends'), findsOneWidget);
    expect(find.text('Add Extra Member Name (optional)'), findsNothing);
  });

  test('removing a friend keeps the financial tab and removes the social link',
      () async {
    const friend = TabbyUser(
      id: 'friend-alex',
      displayName: 'Alex',
      email: 'alex@example.com',
      phone: '+639171112233',
      friendCode: 'TAB-7K4P2M',
    );
    final notifier = TabbyNotifier();
    notifier.state = notifier.state.copyWith(
      tabs: [
        BilateralTab(
          id: 'tab-alex',
          counterpart: friend,
          netBalanceCentavos: 25000,
          itemCount: 1,
          entries: const [],
          lastUpdated: DateTime(2026, 9, 17),
        ),
      ],
      friendRequests: [
        _friendRequest(
          id: 'friendship-alex',
          friendId: friend.id,
          status: FriendRequestStatus.accepted,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [tabbyProvider.overrideWith((_) => notifier)],
    );
    addTearDown(container.dispose);

    await notifier.removeFriend(friend.id);

    expect(notifier.state.tabs, hasLength(1));
    expect(notifier.state.tabs.single.netBalanceCentavos, 25000);
    expect(container.read(friendsProvider), isEmpty);
  });

  test('friend removal repository boundary stays safe while offline', () async {
    expect(
      await SupabaseTabbyRepository.instance.removeFriend(
        friendUserId: '00000000-0000-0000-0000-000000000001',
      ),
      isFalse,
    );
  });
}

FriendRequest _friendRequest({
  required String id,
  required String friendId,
  required FriendRequestStatus status,
}) {
  final friend = TabbyUser(
    id: friendId,
    displayName: friendId,
    email: '',
    phone: '',
    friendCode: 'TAB-7K4P2M',
  );
  return FriendRequest(
    id: id,
    requesterId: MockUserFixtures.current.id,
    addresseeId: friendId,
    requester: MockUserFixtures.current,
    addressee: friend,
    status: status,
    createdAt: DateTime(2026, 9, 17),
    currentUserId: MockUserFixtures.current.id,
  );
}

class MockUserFixtures {
  static const current = TabbyUser(
    id: 'user-me',
    displayName: 'Frienzal',
    email: 'frienzal@tabby.ph',
    phone: '+639178881234',
    friendCode: 'TAB-9N6R3Q',
  );
}
