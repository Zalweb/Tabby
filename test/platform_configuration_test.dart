import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory projectRoot;

  setUpAll(() {
    projectRoot = Directory.current;
    while (!File('${projectRoot.path}/pubspec.yaml').existsSync() &&
        projectRoot.path != projectRoot.parent.path) {
      projectRoot = projectRoot.parent;
    }
  });

  test('Android declares camera access and the Supabase callback deep link',
      () {
    final manifest = File(
      '${projectRoot.path}/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.CAMERA'));
    expect(
      manifest,
      contains(
        'android:scheme="io.supabase.tabby" android:host="login-callback"',
      ),
    );
    expect(manifest, contains('android:launchMode="singleTop"'));
  });

  test('iOS declares native OAuth, callback, and media permissions', () {
    final plist = File(
      '${projectRoot.path}/ios/Runner/Info.plist',
    ).readAsStringSync();

    expect(plist, contains('<key>NSCameraUsageDescription</key>'));
    expect(plist, contains('<key>NSPhotoLibraryUsageDescription</key>'));
    expect(plist, contains('io.supabase.tabby'));
    expect(
      plist,
      contains(
        'com.googleusercontent.apps.137141086000-qnr5kedgh9miig5mmaaq90efn90gckmm',
      ),
    );
  });

  test('iOS release workflow patches Info.plist idempotently', () {
    final workflow = File(
      '${projectRoot.path}/.github/workflows/build-ios.yml',
    ).readAsStringSync();

    expect(workflow, contains('plistlib'));
    expect(workflow, contains('google_entry'));
    expect(workflow, contains('supabase_entry'));
    expect(workflow, isNot(contains('PlistBuddy -c "Add :CFBundleURLTypes:0')));
  });
}
