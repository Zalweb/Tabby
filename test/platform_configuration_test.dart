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

  test(
    'Android declares camera access and the Supabase callback deep link',
    () {
      final manifest = File(
        '${projectRoot.path}/android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final gradle = File('${projectRoot.path}/android/app/build.gradle.kts')
          .readAsStringSync();

      expect(manifest, contains('android.permission.CAMERA'));
      expect(
        manifest,
        contains(
          r'android:scheme="${tabbyAuthScheme}" android:host="login-callback"',
        ),
      );
      expect(gradle, contains('else "io.supabase.tabby"'));
      expect(gradle, contains('"io.supabase.tabby.usbtest"'));
      expect(manifest, contains('android:launchMode="singleTop"'));
    },
  );

  test(
    'Android excludes device-bound account data from backup and transfer',
    () {
      final base = '${projectRoot.path}/android/app/src/main';
      final manifest = File('$base/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      for (final resource in ['backup_rules', 'data_extraction_rules']) {
        final rules = File('$base/res/xml/$resource.xml').readAsStringSync();
        for (final domain in [
          'root',
          'file',
          'database',
          'sharedpref',
          'external',
        ]) {
          expect(rules, contains('<exclude domain="$domain" path="." />'));
        }
      }
      final transfer = File('$base/res/xml/data_extraction_rules.xml')
          .readAsStringSync();
      expect(transfer, contains('<cloud-backup>'));
      expect(transfer, contains('<device-transfer>'));
    },
  );

  test('Android scheduled reminders declare private alarm and reboot receivers', () {
    final manifest = File(
      '${projectRoot.path}/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    for (final receiver in [
      'ScheduledNotificationReceiver',
      'ScheduledNotificationBootReceiver',
    ]) {
      expect(
        RegExp(
          '<receiver[^>]*android:name="com.dexterous.flutterlocalnotifications.$receiver"[^>]*android:exported="false"',
          dotAll: true,
        ).hasMatch(manifest),
        isTrue,
      );
    }
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
  });

  test('iOS declares native OAuth, callback, and media permissions', () {
    final plist = File('${projectRoot.path}/ios/Runner/Info.plist')
        .readAsStringSync();

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
    final workflow = File('${projectRoot.path}/.github/workflows/build-ios.yml')
        .readAsStringSync();
    final prepare = File('${projectRoot.path}/scripts/ios-prepare.py')
        .readAsStringSync();
    expect(workflow, contains('scripts/ios-prepare.py'));
    expect(prepare, contains('plistlib'));
    expect(prepare, contains('google_entry'));
    expect(prepare, contains('supabase_entry'));
    expect(workflow, isNot(contains('PlistBuddy -c "Add :CFBundleURLTypes:0')));
  });
}
