import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS forwards notification presentation and taps through Flutter at launch', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final launch = delegate.substring(
      delegate.indexOf('didFinishLaunchingWithOptions'),
      delegate.indexOf('func didInitializeImplicitFlutterEngine'),
    );
    final registration = launch.indexOf(
      'UNUserNotificationCenter.current().delegate = self',
    );
    expect(delegate, contains('import UserNotifications'));
    expect(registration, greaterThanOrEqualTo(0));
    expect(registration, lessThan(launch.indexOf('return super.application')));
    // Flutter's implicit-engine plugin registry remains the lifecycle owner.
    expect(
      delegate,
      contains(
        'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)',
      ),
    );
  });
}
