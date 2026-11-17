import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/account_push_controller.dart';
import 'package:tabby/core/services/notification_tap_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'remote registration acknowledgment precedes native activation',
    () async {
      final reply = Completer<void>(), entered = Completer<void>();
      final native = <String?>[];
      final controller = AccountPushController(
        nativeScope: (actor, binding) async {
          native.add(actor);
        },
        token: () async => 'synthetic-token',
        register: (_, __, ___) {
          entered.complete();
          return reply.future;
        },
        revoke: (_, __) async {},
      );
      await controller.bind('a', 1);
      final result = controller.synchronize(enabled: true);
      await entered.future;
      expect(native.whereType<String>(), isEmpty);
      reply.complete();
      expect(await result, isTrue);
      expect(native.last, 'a');
    },
  );
  test('account change immediately clears display and serializes after old registration', () async {
    final reply = Completer<void>(), entered = Completer<void>();
    String? displayed;
    var registrations = 0;
    final controller = AccountPushController(
      nativeScope: (actor, binding) async {
        displayed = actor;
      },
      token: () async => 'synthetic-token',
      register: (_, __, ___) async {
        registrations++;
        if (registrations == 1) {
          entered.complete();
          await reply.future;
        }
      },
      revoke: (_, __) async {},
    );
    await controller.bind('a', 1);
    final a = controller.synchronize(enabled: true);
    await entered.future;
    final change = controller.bind('b', 2);
    expect(displayed, isNull);
    final b = controller.synchronize(enabled: true);
    reply.complete();
    expect(await a, isFalse);
    await change;
    expect(await b, isTrue);
    expect(displayed, 'b');
    expect(registrations, 2);
  });
  test('same-account new session invalidates an old token response', () async {
    final token = Completer<String?>(), entered = Completer<void>();
    var registered = false;
    final controller = AccountPushController(
      nativeScope: (_, __) async {},
      token: () {
        entered.complete();
        return token.future;
      },
      register: (_, __, ___) async {
        registered = true;
      },
      revoke: (_, __) async {},
    );
    await controller.bind('a', 1);
    final first = controller.synchronize(enabled: true);
    await entered.future;
    final change = controller.bind('a', 2);
    token.complete('synthetic-token');
    expect(await first, isFalse);
    await change;
    expect(registered, isFalse);
  });
  test('failed/offline registration stays inactive and can retry', () async {
    var failed = true;
    String? native;
    final controller = AccountPushController(
      nativeScope: (actor, binding) async {
        native = actor;
      },
      token: () async => 'synthetic-token',
      register: (_, __, ___) async {
        if (failed) throw StateError('Offline');
      },
      revoke: (_, __) async {},
    );
    await controller.bind('a', 1);
    await expectLater(controller.synchronize(enabled: true), throwsStateError);
    expect(native, isNull);
    failed = false;
    expect(await controller.synchronize(enabled: true), isTrue);
    expect(native, 'a');
  });
  test('disable invalidates native first and retains failed remote revocation for retry', () async {
    var failed = true;
    String? native;
    var revokes = 0;
    final controller = AccountPushController(
      nativeScope: (actor, binding) async {
        native = actor;
      },
      token: () async => 'synthetic-token',
      register: (_, __, ___) async {},
      revoke: (_, __) async {
        revokes++;
        if (failed) throw StateError('Offline');
      },
    );
    await controller.bind('a', 1);
    await controller.synchronize(enabled: true);
    await expectLater(controller.synchronize(enabled: false), throwsStateError);
    expect(native, isNull);
    expect(
      await const FlutterSecureStorage().read(
        key: 'tabby_push_registration_v1',
      ),
      isNotNull,
    );
    failed = false;
    expect(await controller.synchronize(enabled: false), isFalse);
    expect(revokes, 2);
    expect(
      await const FlutterSecureStorage().read(
        key: 'tabby_push_registration_v1',
      ),
      isNull,
    );
  });
  test(
    'missing Firebase configuration does not register or activate',
    () async {
      var registered = false;
      String? native;
      final controller = AccountPushController(
        nativeScope: (actor, binding) async {
          native = actor;
        },
        token: () async => null,
        register: (_, __, ___) async {
          registered = true;
        },
        revoke: (_, __) async {},
      );
      await controller.bind('a', 1);
      expect(await controller.synchronize(enabled: true), isFalse);
      expect(registered, isFalse);
      expect(native, isNull);
    },
  );

  const tab = '00000000-0000-4000-8000-000000000001';
  test('cold tap waits for authenticated account and checks membership before routing', () async {
    final routes = <String>[];
    var reads = 0;
    final taps = NotificationTapCoordinator(
      prepareTab: (_, __) async => true,
      canOpenTab: (actor, id) async {
        reads++;
        return true;
      },
      navigate: routes.add,
    );
    taps.receive({'account': 'a', 'route': 'tab:$tab'});
    await taps.flush(actor: null, current: () => true);
    expect(reads, 0);
    await taps.flush(actor: 'a', current: () => true);
    expect(routes, ['/tabs/$tab']);
    expect(reads, 1);
    await taps.flush(actor: 'a', current: () => true);
    expect(reads, 1);
  });
  test(
    'foreign account, forged route and removed tab never navigate',
    () async {
      final routes = <String>[];
      final taps = NotificationTapCoordinator(
        prepareTab: (_, __) async => true,
        canOpenTab: (_, __) async => false,
        navigate: routes.add,
      );
      for (final payload in [
        {'account': 'b', 'route': 'tab:$tab'},
        {'account': 'a', 'route': 'tab:../../private'},
        {'account': 'a', 'route': 'tab:$tab'},
        {'account': 'a', 'route': 'https://example.test'},
      ]) {
        taps.receive(payload);
        await taps.flush(actor: 'a', current: () => true);
      }
      expect(routes, isEmpty);
    },
  );
  test(
    'account change during authorization discards delayed navigation',
    () async {
      final visible = Completer<bool>(), entered = Completer<void>();
      var current = true;
      final routes = <String>[];
      final taps = NotificationTapCoordinator(
        prepareTab: (_, __) async => true,
        canOpenTab: (_, __) {
          entered.complete();
          return visible.future;
        },
        navigate: routes.add,
      );
      taps.receive({'account': 'a', 'route': 'tab:$tab'});
      final flush = taps.flush(actor: 'a', current: () => current);
      await entered.future;
      current = false;
      visible.complete(true);
      await flush;
      expect(routes, isEmpty);
    },
  );
  test('transient authorization failure can retry without trusting cached membership', () async {
    var failed = true;
    final routes = <String>[];
    final taps = NotificationTapCoordinator(
      prepareTab: (_, __) async => true,
      canOpenTab: (_, __) async {
        if (failed) throw StateError('Offline');
        return true;
      },
      navigate: routes.add,
    );
    taps.receive({'account': 'a', 'route': 'tab:$tab'});
    await taps.flush(actor: 'a', current: () => true);
    expect(routes, isEmpty);
    failed = false;
    await taps.flush(actor: 'a', current: () => true);
    expect(routes, ['/tabs/$tab']);
  });
}
