import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/connections/application/connection_preferences.dart';
import 'package:tabby/features/connections/presentation/connections_screen.dart';
import 'package:tabby/features/connections/presentation/private_nickname_sheet.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const me = TabbyUser(
    id: 'user-me', displayName: 'Owner fixture', email: '', phone: '');
const friend = TabbyUser(
    id: 'friend-fixture',
    displayName: 'Canonical Friend',
    email: '',
    phone: '',
    friendCode: 'TAB-7K4P2M');
Map<String, dynamic> snapshot(
        {int revision = 0, String? name, List<String> archived = const []}) =>
    {
      'revision': revision,
      'nicknames': {if (name != null) friend.id: name},
      'archived_tab_ids': archived
    };
ConnectionPreferencesNotifier preferences(
        {String owner = 'user-me',
        bool Function()? current,
        Future<Map<String, dynamic>> Function()? read,
        Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
            change,
        FlutterSecureStorage storage = const FlutterSecureStorage()}) =>
    ConnectionPreferencesNotifier(
        owner: owner,
        current: current ?? () => true,
        readRemote: read,
        changeRemote: change,
        storage: storage);
TabbyNotifier dashboard() {
  final notifier = TabbyNotifier(loadInitialData: false);
  notifier.state = notifier.state.copyWith(viewerUserId: me.id, tabs: [
    BilateralTab(
        id: 'group-fixture',
        counterpart: friend,
        isGroupTab: true,
        groupName: 'Group fixture',
        netBalanceCentavos: 4000,
        itemCount: 0,
        entries: const [],
        lastUpdated: DateTime(2026, 11, 1))
  ], friendRequests: [
    FriendRequest(
        id: 'friendship-fixture',
        requesterId: me.id,
        addresseeId: friend.id,
        requester: me,
        addressee: friend,
        status: FriendRequestStatus.accepted,
        createdAt: DateTime(2026, 11, 1),
        currentUserId: me.id)
  ]);
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'private names and archive survive restart without altering another account',
      () async {
    final first = preferences();
    await first.ready;
    expect(await first.change('nickname', friend.id, nickname: 'Private label'),
        isTrue);
    expect(await first.change('archive', 'group-fixture'), isTrue);
    first.dispose();
    final restored = preferences();
    await restored.ready;
    expect(restored.state.nicknames[friend.id], 'Private label');
    expect(restored.state.archived, {'group-fixture'});
    final other = preferences(owner: 'other-owner');
    await other.ready;
    expect(other.state.nicknames, isEmpty);
    expect(other.state.archived, isEmpty);
    expect(friend.displayName, 'Canonical Friend');
    restored.dispose();
    other.dispose();
  });
  test(
      'waits for server acknowledgment, retains failure and reuses uncertain operation',
      () async {
    final ack = Completer<Map<String, dynamic>>();
    var fail = true, remote = snapshot();
    final operations = <String>[];
    final prefs = preferences(
        read: () async => remote,
        change: (operation, command) {
          operations.add(operation);
          expect(command['owner_id'], me.id);
          if (fail) return ack.future;
          remote = snapshot(revision: 1, name: 'Requested');
          return Future.value(remote);
        });
    await prefs.ready;
    final pending = prefs.change('nickname', friend.id, nickname: 'Requested');
    await Future<void>.delayed(Duration.zero);
    expect(prefs.state.nicknames, isEmpty);
    ack.completeError(StateError('Synthetic response loss'));
    expect(await pending, isFalse);
    expect(prefs.state.nicknames, isEmpty);
    fail = false;
    expect(await prefs.change('nickname', friend.id, nickname: 'Requested'),
        isTrue);
    expect(operations, hasLength(2));
    expect(operations[0], operations[1]);
    prefs.dispose();
  });
  test(
      'late response after account/session change never changes state or cache',
      () async {
    var current = true;
    final ack = Completer<Map<String, dynamic>>();
    final prefs = preferences(
        current: () => current,
        read: () async => snapshot(),
        change: (_, command) => ack.future);
    await prefs.ready;
    final pending =
        prefs.change('nickname', friend.id, nickname: 'Late private name');
    await Future<void>.delayed(Duration.zero);
    current = false;
    ack.complete(snapshot(revision: 1, name: 'Late private name'));
    expect(await pending, isFalse);
    expect(prefs.state.nicknames, isEmpty);
    expect(await const FlutterSecureStorage().read(key: prefs.key),
        isNot(contains('Late private name')));
    prefs.dispose();
  });
  test('revision conflict refreshes and requires a new deliberate retry',
      () async {
    var remote = snapshot();
    final prefs = preferences(
        read: () async => remote,
        change: (_, command) async {
          remote = snapshot(revision: 2, name: 'Other device');
          throw const PostgrestException(message: 'Stale', code: '40001');
        });
    await prefs.ready;
    expect(await prefs.change('nickname', friend.id, nickname: 'My edit'),
        isFalse);
    expect(prefs.state.revision, 2);
    expect(prefs.state.nicknames[friend.id], 'Other device');
    expect(prefs.state.error, contains('Review'));
    prefs.dispose();
  });
  test(
      'replayed earlier acknowledgment cannot replace a newer authoritative view',
      () async {
    var remote = snapshot();
    final prefs = preferences(
        read: () async => remote,
        change: (_, command) async {
          remote = snapshot(revision: 3, name: 'Latest');
          return snapshot(revision: 1, name: 'Older replay');
        });
    await prefs.ready;
    expect(await prefs.change('nickname', friend.id, nickname: 'Older replay'),
        isTrue);
    expect(prefs.state.nicknames[friend.id], 'Latest');
    expect(prefs.state.revision, 3);
    expect(await const FlutterSecureStorage().read(key: prefs.key),
        contains('Latest'));
    prefs.dispose();
  });
  test('reentrant changes submit one command', () async {
    final ack = Completer<Map<String, dynamic>>();
    var calls = 0;
    final prefs = preferences(
        read: () async => snapshot(),
        change: (_, command) {
          calls++;
          return ack.future;
        });
    await prefs.ready;
    final pending = prefs.change('archive', 'group-fixture');
    expect(await prefs.change('restore', 'group-fixture'), isFalse);
    expect(calls, 1);
    ack.complete(snapshot(revision: 1, archived: ['group-fixture']));
    await pending;
    prefs.dispose();
  });
  test('local persistence failure cannot claim a saved private label',
      () async {
    final storage = ToggleConnectionStorage();
    final prefs = preferences(storage: storage);
    await prefs.ready;
    storage.fail = true;
    expect(await prefs.change('nickname', friend.id, nickname: 'Unsaved'),
        isFalse);
    expect(prefs.state.nicknames, isEmpty);
    prefs.dispose();
  });
  test('acknowledged server change remains accepted when cache writing fails',
      () async {
    final storage = ToggleConnectionStorage();
    var remote = snapshot();
    final prefs = preferences(
        storage: storage,
        read: () async => remote,
        change: (_, command) async {
          remote = snapshot(revision: 1, name: 'Server saved');
          return remote;
        });
    await prefs.ready;
    storage.fail = true;
    expect(await prefs.change('nickname', friend.id, nickname: 'Server saved'),
        isTrue);
    expect(prefs.state.nicknames[friend.id], 'Server saved');
    prefs.dispose();
  });
  test('valid authoritative read repairs corrupt disposable preference cache',
      () async {
    await const FlutterSecureStorage()
        .write(key: 'tabby_user-me_connections_v1', value: 'corrupt fixture');
    final prefs =
        preferences(read: () async => snapshot(revision: 2, name: 'Recovered'));
    await prefs.ready;
    expect(prefs.state.loaded, isTrue);
    expect(prefs.state.nicknames[friend.id], 'Recovered');
    prefs.dispose();
  });
  test('self/unsupported commands do not submit', () async {
    var calls = 0;
    final prefs = preferences(
        read: () async => snapshot(),
        change: (_, command) async {
          calls++;
          return snapshot();
        });
    await prefs.ready;
    expect(await prefs.change('nickname', me.id, nickname: 'Self'), isFalse);
    expect(await prefs.change('delete', 'group-fixture'), isFalse);
    expect(calls, 0);
    prefs.dispose();
  });
  test(
      'unfriend waits and preserves financial tabs on rejection and acceptance',
      () async {
    final notifier = dashboard();
    final original = notifier.state.tabs;
    final ack = Completer<bool>();
    final pending = notifier.removeFriend(friend.id, persist: () => ack.future);
    expect(notifier.state.friendRequests.single.status,
        FriendRequestStatus.accepted);
    ack.complete(false);
    expect(await pending, isFalse);
    expect(notifier.state.tabs, same(original));
    expect(await notifier.removeFriend(friend.id, persist: () async => true),
        isTrue);
    expect(notifier.state.friendRequests.single.status,
        FriendRequestStatus.declined);
    expect(notifier.state.tabs, same(original));
    expect(notifier.state.tabs.single.netBalanceCentavos, 4000);
    notifier.dispose();
  });
  test(
      'unfriend late account result and thrown transport cannot alter new actor state',
      () async {
    final notifier = dashboard();
    final ack = Completer<bool>();
    final pending = notifier.removeFriend(friend.id, persist: () => ack.future);
    notifier.state = notifier.state.copyWith(viewerUserId: 'new-actor');
    ack.complete(true);
    expect(await pending, isFalse);
    expect(notifier.state.friendRequests.single.status,
        FriendRequestStatus.accepted);
    expect(
        await notifier.removeFriend(friend.id,
            persist: () async => throw StateError('offline')),
        isFalse);
    notifier.dispose();
  });

  Future<void> show(WidgetTester tester, ConnectionPreferencesNotifier prefs,
      {TabbyNotifier? ledger, bool nickname = false}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          connectionPreferencesProvider.overrideWith((_) => prefs),
          currentUserProvider.overrideWith(
              (_) => CurrentUserNotifier(initialUser: me, autoLoad: false)),
          tabbyProvider.overrideWith((_) => ledger ?? dashboard())
        ],
        child: MaterialApp(
            home: nickname
                ? Builder(
                    builder: (context) => Scaffold(
                        body: TextButton(
                            onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) =>
                                    const PrivateNicknameSheet(friend: friend)),
                            child: const Text('Open nickname'))))
                : const ConnectionsScreen())));
    await tester.pumpAndSettle();
    if (nickname) {
      await tester.tap(find.text('Open nickname'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('nickname rejection preserves draft and canonical profile',
      (tester) async {
    final prefs = preferences(
        read: () async => snapshot(),
        change: (_, command) async => throw StateError('Synthetic rejection'));
    await prefs.ready;
    await show(tester, prefs, nickname: true);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Retained nickname');
    await tester.tap(find.text('Save nickname'));
    await tester.pumpAndSettle();
    expect(find.text('Retained nickname'), findsOneWidget);
    expect(find.text('Private nickname saved.'), findsNothing);
    expect(friend.displayName, 'Canonical Friend');
    expect(prefs.state.nicknames, isEmpty);
  });
  testWidgets(
      'private archive hides only Connections and restores the same unpaid group',
      (tester) async {
    final prefs = preferences();
    await prefs.ready;
    final ledger = dashboard();
    final original = ledger.state.tabs;
    await show(tester, prefs, ledger: ledger);
    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Group options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('balances and reminders stay available'),
        findsOneWidget);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Group fixture'), findsNothing);
    expect(ledger.state.tabs, same(original));
    await tester.tap(find.text('Show archived connections'));
    await tester.pumpAndSettle();
    expect(find.text('Group fixture'), findsOneWidget);
    await tester.tap(find.byTooltip('Group options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Group fixture'), findsNothing);
    await tester.tap(find.text('Show archived connections'));
    await tester.pumpAndSettle();
    expect(find.text('Group fixture'), findsOneWidget);
    expect(ledger.state.tabs.single.netBalanceCentavos, 4000);
  });
  testWidgets(
      'failed archive keeps the confirmation open and never claims deletion',
      (tester) async {
    final prefs = preferences(
        read: () async => snapshot(),
        change: (_, command) async =>
            throw StateError('Synthetic network failure'));
    await prefs.ready;
    await show(tester, prefs);
    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Group options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Change could not be verified. Please retry.'),
        findsOneWidget);
    expect(prefs.state.archived, isEmpty);
    expect(find.textContaining('has been deleted'), findsNothing);
  });
  testWidgets(
      'obsolete nickname response cannot close the new account home or announce a save',
      (tester) async {
    var current = true;
    final ack = Completer<Map<String, dynamic>>();
    final prefs = preferences(
        current: () => current,
        read: () async => snapshot(),
        change: (_, command) => ack.future);
    await prefs.ready;
    await show(tester, prefs, nickname: true);
    await tester.enterText(find.byType(TextField), 'Old actor edit');
    await tester.tap(find.text('Save nickname'));
    await tester.pump();
    current = false;
    SupabaseConfig.sessionRevision.value++;
    await tester.pumpAndSettle();
    ack.complete(snapshot(revision: 1, name: 'Old actor edit'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivateNicknameSheet), findsNothing);
    expect(find.text('Open nickname'), findsOneWidget);
    expect(find.text('Private nickname saved.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class ToggleConnectionStorage extends FlutterSecureStorage {
  bool fail = false;
  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (fail) throw StateError('Synthetic cache failure');
    await super.write(
        key: key,
        value: value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions);
  }
}
