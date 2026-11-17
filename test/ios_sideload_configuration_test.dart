import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iOS OAuth uses app_links without a competing Flutter route handler',
    () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(
        RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false\s*/>')
            .hasMatch(plist),
        isTrue,
      );
      expect(plist, contains('io.supabase.tabby'));
      expect(plist, contains('<key>NSFaceIDUsageDescription</key>'));
    },
  );
  test('unsigned build preserves checked-in native code and keeps client config outside source', () {
    final workflow = File('.github/workflows/build-ios.yml').readAsStringSync();
    expect(workflow, contains('scripts/ios-prepare.py --verify-source'));
    expect(workflow, contains('--no-codesign'));
    expect(workflow, contains('scripts/ios-package.py'));
    expect(workflow, contains('integration_test/ios_native_smoke_test.dart'));
    expect(workflow, isNot(contains('flutter create')));
    expect(workflow, isNot(contains('> .env')));
    expect(workflow, isNot(contains('dart run flutter_launcher_icons')));
    expect(
      File('ios/Podfile').readAsStringSync(),
      contains('flutter_install_all_ios_pods'),
    );
    for (final mode in ['Debug', 'Release']) {
      expect(
        File('ios/Flutter/$mode.xcconfig').readAsStringSync(),
        contains('Pods-Runner.'),
      );
    }
  });
}
