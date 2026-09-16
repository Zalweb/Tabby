import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android launcher activity uses the app namespace', () {
    var projectRoot = Directory.current;
    while (!File('${projectRoot.path}/pubspec.yaml').existsSync() &&
        projectRoot.path != projectRoot.parent.path) {
      projectRoot = projectRoot.parent;
    }

    final gradle = File(
      '${projectRoot.path}/android/app/build.gradle.kts',
    ).readAsStringSync();
    final manifest = File(
      '${projectRoot.path}/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final supabaseConfig = File(
      '${projectRoot.path}/supabase/config.toml',
    ).readAsStringSync();
    final activityFiles = Directory(
      '${projectRoot.path}/android/app/src/main/kotlin',
    )
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.uri.pathSegments.last == 'MainActivity.kt')
        .toList();

    expect(activityFiles, hasLength(1));
    final activity = activityFiles.single.readAsStringSync();

    expect(gradle, contains('namespace = "com.zalweb.tabby"'));
    expect(gradle, contains('applicationId = "com.zalweb.tabby"'));
    expect(manifest, contains('android:name=".MainActivity"'));
    expect(activity, contains('package com.zalweb.tabby'));
    expect(supabaseConfig, contains('"io.supabase.tabby://login-callback"'));
  });
}
