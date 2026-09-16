import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';

void main() {
  const iosClientId = 'ios-client.apps.googleusercontent.com';
  const webClientId = 'web-client.apps.googleusercontent.com';

  test('Android does not use the iOS client ID', () {
    final configuration = googleSignInClientConfiguration(
      platform: TargetPlatform.android,
      iosClientId: iosClientId,
      webClientId: webClientId,
    );

    expect(configuration.clientId, isNull);
  });

  test('Android uses the Web client as its server client ID', () {
    final configuration = googleSignInClientConfiguration(
      platform: TargetPlatform.android,
      iosClientId: iosClientId,
      webClientId: webClientId,
    );

    expect(configuration.serverClientId, webClientId);
  });

  test('iOS uses the iOS client ID as its platform client ID', () {
    final configuration = googleSignInClientConfiguration(
      platform: TargetPlatform.iOS,
      iosClientId: iosClientId,
      webClientId: webClientId,
    );

    expect(configuration.clientId, iosClientId);
  });
}
