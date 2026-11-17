import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/notification_tap_coordinator.dart';

void main() {
  const tab = '00000000-0000-4000-8000-000000000001';

  test(
    'authorized notification opens a newly received tab after cache loading',
    () async {
      String? cachedTab;
      String? openedTab;
      final taps = NotificationTapCoordinator(
        canOpenTab: (_, __) async => true,
        prepareTab: (_, requested) async {
          cachedTab = requested;
          return true;
        },
        navigate: (_) => openedTab = cachedTab,
      );
      taps.receive({'account': 'synthetic-account', 'route': 'tab:$tab'});
      await taps.flush(actor: 'synthetic-account', current: () => true);
      expect(
        openedTab,
        tab,
        reason: 'Permission alone must not navigate to a missing local tab.',
      );
    },
  );

  test('navigation waits for the authorized target load', () async {
    final entered = Completer<void>(), loaded = Completer<bool>();
    final routes = <String>[];
    final taps = NotificationTapCoordinator(
      canOpenTab: (_, __) async => true,
      prepareTab: (_, __) {
        entered.complete();
        return loaded.future;
      },
      navigate: routes.add,
    );
    taps.receive({'account': 'a', 'route': 'tab:$tab'});
    final flush = taps.flush(actor: 'a', current: () => true);
    await entered.future;
    expect(routes, isEmpty);
    loaded.complete(true);
    await flush;
    expect(routes, ['/tabs/$tab']);
  });

  test('unavailable target stays pending and can retry', () async {
    var ready = false;
    final routes = <String>[];
    final taps = NotificationTapCoordinator(
      canOpenTab: (_, __) async => true,
      prepareTab: (_, __) async => ready,
      navigate: routes.add,
    );
    taps.receive({'account': 'a', 'route': 'tab:$tab'});
    await taps.flush(actor: 'a', current: () => true);
    expect(routes, isEmpty);
    ready = true;
    await taps.flush(actor: 'a', current: () => true);
    expect(routes, ['/tabs/$tab']);
  });

  test(
    'later account cannot receive navigation after a delayed load',
    () async {
      final entered = Completer<void>(), loaded = Completer<bool>();
      var current = true;
      final routes = <String>[];
      final taps = NotificationTapCoordinator(
        canOpenTab: (_, __) async => true,
        prepareTab: (_, __) {
          entered.complete();
          return loaded.future;
        },
        navigate: routes.add,
      );
      taps.receive({'account': 'a', 'route': 'tab:$tab'});
      final flush = taps.flush(actor: 'a', current: () => current);
      await entered.future;
      current = false;
      loaded.complete(true);
      await flush;
      expect(routes, isEmpty);
    },
  );

  test('denied membership never prepares a target', () async {
    var prepared = 0;
    final routes = <String>[];
    final taps = NotificationTapCoordinator(
      canOpenTab: (_, __) async => false,
      prepareTab: (_, __) async {
        prepared++;
        return true;
      },
      navigate: routes.add,
    );
    taps.receive({'account': 'a', 'route': 'tab:$tab'});
    await taps.flush(actor: 'a', current: () => true);
    expect(prepared, 0);
    expect(routes, isEmpty);
  });

  test('newer tap supersedes an older delayed target load', () async {
    const later = '00000000-0000-4000-8000-000000000002';
    final entered = Completer<void>(), loaded = Completer<bool>();
    final routes = <String>[];
    final taps = NotificationTapCoordinator(
      canOpenTab: (_, __) async => true,
      prepareTab: (_, requested) {
        if (requested == tab) {
          entered.complete();
          return loaded.future;
        }
        return Future.value(true);
      },
      navigate: routes.add,
    );
    taps.receive({'account': 'a', 'route': 'tab:$tab'});
    final flush = taps.flush(actor: 'a', current: () => true);
    await entered.future;
    taps.receive({'account': 'a', 'route': 'tab:$later'});
    loaded.complete(true);
    await flush;
    expect(routes, ['/tabs/$later']);
  });
}
