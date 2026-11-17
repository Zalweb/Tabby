import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/account_notification_controller.dart';
import 'package:tabby/core/services/notification_preferences.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  const store = NotificationPreferencesStore();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'existing immediate notification receipts still suppress duplicates',
    () async {
      final ports = FakeAlerts();
      await ports.bind();
      await store.save('a', const NotificationPreferences(enabled: true));
      await storage.write(
        key: 'tabby_a_notification_registry_v1',
        value: jsonEncode({
          'payment': {
            'id': 7,
            'kind': 'payment',
            'signature': sha256.convert(utf8.encode('payment')).toString(),
          },
        }),
      );
      expect(
        await ports.send('payment', kind: NotificationKind.payment),
        isFalse,
      );
      expect(ports.shown, isEmpty);
    },
  );

  test('fresh account defaults off and never inherits global or other account keys', () async {
    FlutterSecureStorage.setMockInitialValues({
      'tabby_notifications_enabled': 'true',
      'tabby_a_notifications_enabled': 'true',
      'tabby_a_payment_alerts_enabled': 'false',
    });
    expect((await store.load('b')).enabled, isFalse);
    expect((await store.load('a')).enabled, isTrue);
    expect((await store.load('a')).payments, isFalse);
    await store.save(
      'a',
      const NotificationPreferences(enabled: true, reminders: false),
    );
    expect((await store.load('a')).payments, isTrue);
    expect((await store.load('a')).reminders, isFalse);
    expect((await store.load('b')).enabled, isFalse);
  });

  test(
    'malformed scoped preferences fail closed without falling back',
    () async {
      await storage.write(
        key: 'tabby_a_notification_preferences_v1',
        value: '{"enabled":"true"}',
      );
      expect(() => store.load('a'), throwsFormatException);
    },
  );

  test(
    'permission denial and disabled categories prevent device writes',
    () async {
      final ports = FakeAlerts(permission: false);
      await ports.bind();
      await store.save(
        'a',
        const NotificationPreferences(enabled: true, payments: false),
      );
      expect(await ports.send('reminder'), isFalse);
      ports.allowed = true;
      expect(
        await ports.send('payment', kind: NotificationKind.payment),
        isFalse,
      );
      expect(await ports.send('reminder'), isTrue);
      expect(ports.shown, ['a:7']);
    },
  );

  test('stable collision-safe IDs deduplicate accepted events and retry failed ports', () async {
    final ports = FakeAlerts();
    await ports.bind();
    await store.save('a', const NotificationPreferences(enabled: true));
    expect(await ports.send('one'), isTrue);
    expect(await ports.send('one'), isFalse);
    expect(await ports.send('two'), isTrue);
    expect(ports.shown, ['a:7', 'a:8']);
    ports.fail = true;
    await expectLater(ports.send('three'), throwsStateError);
    ports.fail = false;
    expect(await ports.send('three'), isTrue);
    expect(ports.shown.last, 'a:9');
    // Legacy IDs may collide with another registered reminder. Do not cancel it.
    await ports.controller.cancelKey('one', legacyIds: {8, 99});
    expect(ports.cancelled, [7, 99]);
  });

  test(
    'scheduled events reconcile missing OS requests after restart',
    () async {
      final ports = FakeAlerts();
      await ports.bind();
      await store.save('a', const NotificationPreferences(enabled: true));
      expect(await ports.send('due', scheduled: true), isTrue);
      expect(await ports.send('due', scheduled: true), isFalse);
      ports.pending.clear();
      expect(await ports.send('due', scheduled: true), isTrue);
      expect(ports.shown, ['a:7', 'a:7']);
    },
  );

  test(
    'alarm access change rearms a persisted OS request with the same ID',
    () async {
      final ports = FakeAlerts();
      await ports.bind();
      await store.save('a', const NotificationPreferences(enabled: true));
      final sent = <int>[];
      Future<bool> schedule(String policy) => ports.controller.notify(
        key: 'due',
        kind: NotificationKind.reminder,
        signature: 'same due date',
        scheduled: true,
        deliveryPolicy: policy,
        send: (id, _) async {
          sent.add(id);
          ports.pending.add(id);
        },
      );
      expect(await schedule('exact'), isTrue);
      expect(await schedule('exact'), isFalse);
      // Plugin persistence can survive Android cancelling the actual alarm.
      expect(await schedule('inexact'), isTrue);
      expect(await schedule('inexact'), isFalse);
      expect(await schedule('exact'), isTrue);
      expect(sent, [7, 7, 7]);
      await store.save('a', const NotificationPreferences());
      expect(await schedule('inexact'), isFalse);
    },
  );

  test(
    'disable cancels only the selected category then master cancels all',
    () async {
      final ports = FakeAlerts();
      await ports.bind();
      await store.save('a', const NotificationPreferences(enabled: true));
      await ports.send('due', scheduled: true);
      await ports.send('payment', kind: NotificationKind.payment);
      await store.save(
        'a',
        const NotificationPreferences(enabled: true, reminders: false),
      );
      await ports.controller.preferencesChanged('a');
      expect(ports.cancelled, [7]);
      expect(ports.cancelsAll, 1); // Initial account bind.
      await store.save('a', const NotificationPreferences());
      await ports.controller.preferencesChanged('a');
      expect(ports.cancelsAll, 2);
      expect(await ports.send('new'), isFalse);
    },
  );

  test('account transition cancels an in-flight old write before new account delivery', () async {
    final ports = FakeAlerts();
    await ports.bind();
    await store.save('a', const NotificationPreferences(enabled: true));
    await store.save('b', const NotificationPreferences(enabled: true));
    final entered = Completer<void>(), release = Completer<void>();
    final old = ports.controller.notify(
      key: 'old',
      kind: NotificationKind.reminder,
      signature: 'old',
      scheduled: false,
      send: (id, actor) async {
        entered.complete();
        await release.future;
        ports.shown.add('$actor:$id');
      },
    );
    await entered.future;
    final switched = ports.controller.bind('b', session: 2);
    final next = ports.send('new');
    release.complete();
    expect(await old, isFalse);
    await switched;
    expect(await next, isTrue);
    expect(ports.events, ['cancelAll', 'cancelAll', 'send:b:7']);
    expect(await storage.read(key: 'tabby_a_notification_registry_v1'), isNull);
  });

  test(
    'same-account new session discards permission result from prior session',
    () async {
      final permission = Completer<bool>();
      final started = Completer<void>();
      var sent = false;
      final controller = AccountNotificationController(
        preferences: store,
        permission: () {
          started.complete();
          return permission.future;
        },
        cancel: (_) async {},
        cancelAll: () async {},
        pendingIds: () async => {},
      );
      await controller.bind('a', session: 1);
      await store.save('a', const NotificationPreferences(enabled: true));
      final old = controller.notify(
        key: 'event',
        kind: NotificationKind.system,
        signature: 's',
        scheduled: false,
        send: (_, __) async {
          sent = true;
        },
      );
      await started.future;
      final rebind = controller.bind('a', session: 2);
      permission.complete(true);
      expect(await old, isFalse);
      await rebind;
      expect(sent, isFalse);
    },
  );

  test('corrupt preferences cancel pending alerts and do not post', () async {
    final ports = FakeAlerts();
    await ports.bind();
    await storage.write(
      key: 'tabby_a_notification_preferences_v1',
      value: 'bad',
    );
    await expectLater(
      ports.controller.preferencesChanged('a'),
      throwsFormatException,
    );
    expect(ports.cancelsAll, 2);
    await expectLater(ports.send('new'), throwsFormatException);
    expect(ports.shown, isEmpty);
  });

  test(
    'settings await opt-in permission before saving or showing enabled',
    () async {
      final permission = Completer<bool>();
      final notifier = UserSettingsNotifier(
        userId: 'a',
        notificationPermission: () => permission.future,
      );
      addTearDown(notifier.dispose);
      await notifier.ready;
      final enable = notifier.toggleNotifications(true);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.notificationsEnabled, isFalse);
      expect((await store.load('a')).enabled, isFalse);
      permission.complete(false);
      expect(await enable, isFalse);
      expect(notifier.state.notificationsEnabled, isFalse);
      expect(notifier.state.notificationError, contains('not allowed'));
    },
  );

  test(
    'settings persist opt-in and disable without asking for permission again',
    () async {
      var requests = 0, reconciliations = 0;
      final notifier = UserSettingsNotifier(
        userId: 'a',
        notificationPermission: () async {
          requests++;
          return true;
        },
        notificationsChanged: () async {
          reconciliations++;
          return true;
        },
      );
      addTearDown(notifier.dispose);
      await notifier.ready;
      expect(await notifier.toggleNotifications(true), isTrue);
      expect(notifier.state.notificationsEnabled, isTrue);
      expect((await store.load('a')).enabled, isTrue);
      expect(
        await notifier.setNotificationPreferences(payments: false),
        isTrue,
      );
      expect(await notifier.toggleNotifications(false), isTrue);
      expect(requests, 1);
      expect(reconciliations, 4);
      expect((await store.load('a')).enabled, isFalse);
    },
  );

  test(
    'malformed notification settings do not prevent loading security settings',
    () async {
      await storage.write(
        key: 'tabby_a_notification_preferences_v1',
        value: 'invalid',
      );
      final notifier = UserSettingsNotifier(userId: 'a');
      addTearDown(notifier.dispose);
      await notifier.ready;
      expect(notifier.state.isLoaded, isTrue);
      expect(notifier.state.notificationsEnabled, isFalse);
      expect(notifier.state.notificationError, contains('could not be read'));
    },
  );

  test(
    'failed preference persistence keeps opt-in off and reports failure',
    () async {
      final notifier = UserSettingsNotifier(
        userId: 'a',
        storage: FailingPreferenceStorage(),
        notificationPermission: () async => true,
      );
      addTearDown(notifier.dispose);
      await notifier.ready;
      expect(await notifier.toggleNotifications(true), isFalse);
      expect(notifier.state.notificationsEnabled, isFalse);
      expect(notifier.state.notificationError, contains('could not be saved'));
      expect((await store.load('a')).enabled, isFalse);
    },
  );
}

class FailingPreferenceStorage extends FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw StateError('Synthetic storage failure');
  }
}

class FakeAlerts {
  FakeAlerts({bool permission = true}) : allowed = permission {
    controller = AccountNotificationController(
      preferences: const NotificationPreferencesStore(),
      permission: () async => allowed,
      initialId: (_) => 7,
      cancel: (id) async {
        cancelled.add(id);
        pending.remove(id);
      },
      cancelAll: () async {
        cancelsAll++;
        pending.clear();
        events.add('cancelAll');
      },
      pendingIds: () async => pending,
    );
  }
  late final AccountNotificationController controller;
  bool allowed, fail = false;
  int cancelsAll = 0;
  final shown = <String>[], events = <String>[];
  final cancelled = <int>[], pending = <int>{};
  Future<void> bind() => controller.bind('a', session: 1);
  Future<bool> send(
    String key, {
    NotificationKind kind = NotificationKind.reminder,
    bool scheduled = false,
  }) => controller.notify(
    key: key,
    kind: kind,
    signature: key,
    scheduled: scheduled,
    send: (id, actor) async {
      if (fail) throw StateError('port failed');
      shown.add('$actor:$id');
      events.add('send:$actor:$id');
      if (scheduled) pending.add(id);
    },
  );
}
