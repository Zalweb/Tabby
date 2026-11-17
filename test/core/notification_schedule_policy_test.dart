import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/services/notification_schedule_policy.dart';

void main() {
  for (final allowed in [true, false]) {
    test('exact access $allowed selects an available schedule mode', () async {
      final modes = <AndroidScheduleMode>[];
      await NotificationSchedulePolicy.schedule(
          isAndroid: true,
          canScheduleExact: () async => allowed,
          send: (mode) async => modes.add(mode));
      expect(modes, [
        allowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle
      ]);
    });
  }
  test('permission revoked between check and scheduling falls back once',
      () async {
    final modes = <AndroidScheduleMode>[];
    await NotificationSchedulePolicy.schedule(
        isAndroid: true,
        canScheduleExact: () async => true,
        send: (mode) async {
          modes.add(mode);
          if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
            throw PlatformException(code: 'exact_alarms_not_permitted');
          }
        });
    expect(modes, [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle
    ]);
  });
  test('platform capability error falls back to inexact', () async {
    final modes = <AndroidScheduleMode>[];
    await NotificationSchedulePolicy.schedule(
        isAndroid: true,
        canScheduleExact: () async =>
            throw PlatformException(code: 'unavailable'),
        send: (mode) async => modes.add(mode));
    expect(modes, [AndroidScheduleMode.inexactAllowWhileIdle]);
  });
  test('unrelated scheduling errors propagate without duplicate attempts',
      () async {
    var attempts = 0;
    await expectLater(
        NotificationSchedulePolicy.schedule(
            isAndroid: true,
            canScheduleExact: () async => true,
            send: (_) async {
              attempts++;
              throw PlatformException(code: 'invalid_channel');
            }),
        throwsA(isA<PlatformException>()));
    expect(attempts, 1);
  });
  test('other platforms never request Android alarm access', () async {
    var checked = false;
    await NotificationSchedulePolicy.schedule(
        isAndroid: false,
        canScheduleExact: () async {
          checked = true;
          return false;
        },
        send: (_) async {});
    expect(checked, isFalse);
  });
}
