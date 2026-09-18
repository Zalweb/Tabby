import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tabby/features/app_update/data/app_update_service.dart';
import 'package:tabby/features/app_update/domain/app_update_models.dart';
import 'package:tabby/features/app_update/presentation/app_update_prompt.dart';
import 'package:tabby/core/widgets/app_version_footer.dart';

void main() {
  group('AppVersion', () {
    test('parses a release tag and build number', () {
      final version = AppVersion.tryParse('v1.2.3', buildNumber: '4');

      expect(version, const AppVersion(1, 2, 3, 4));
      expect(version!.displayValue, '1.2.3');
      expect(version.fullDisplayValue, '1.2.3+4');
    });

    test('treats a newer build or semantic version as newer', () {
      const installed = AppVersion(1, 2, 3, 4);

      expect(const AppVersion(1, 2, 3, 5).isNewerThan(installed), isTrue);
      expect(const AppVersion(1, 3, 0).isNewerThan(installed), isTrue);
      expect(const AppVersion(1, 2, 3, 4).isNewerThan(installed), isFalse);
      expect(const AppVersion(1, 2, 3, 3).isNewerThan(installed), isFalse);
    });

    test('rejects malformed versions', () {
      expect(AppVersion.tryParse('v1.2'), isNull);
      expect(AppVersion.tryParse('release-latest'), isNull);
    });
  });

  group('GitHub release mapping', () {
    test('maps the latest release and platform assets', () {
      final release = AppUpdateRelease.fromJson({
        'tag_name': 'v1.4.0',
        'body': 'Fresh fixes',
        'html_url': 'https://github.com/Zalweb/Tabby/releases/tag/v1.4.0',
        'assets': [
          {
            'name': 'Tabby-v1.4.0.apk',
            'browser_download_url':
                'https://github.com/Zalweb/Tabby/releases/download/v1.4.0/Tabby-v1.4.0.apk',
          },
          {
            'name': 'Tabby.ipa',
            'browser_download_url':
                'https://github.com/Zalweb/Tabby/releases/download/v1.4.0/Tabby.ipa',
          },
        ],
      });

      expect(release, isNotNull);
      expect(release!.version, const AppVersion(1, 4, 0));
      expect(release.releaseNotes, 'Fresh fixes');
      expect(release.androidDownloadUrl.toString(), endsWith('.apk'));
      expect(release.iosDownloadUrl.toString(), endsWith('.ipa'));
      expect(release.webDownloadUrl.toString(),
          'https://tabby-web-fawn.vercel.app/#download');
    });

    test('ignores malformed release payloads', () {
      expect(AppUpdateRelease.fromJson(const {}), isNull);
      expect(
        AppUpdateRelease.fromJson(const {'tag_name': 'latest'}),
        isNull,
      );
      expect(
        AppUpdateRelease.fromJson(const {
          'tag_name': 'v1.4.0',
          'html_url': 42,
        }),
        isNull,
      );
    });
  });

  group('AppUpdateService', () {
    test('returns a newer release from GitHub metadata', () async {
      final client = _FakeHttpClient(
        statusCode: 200,
        body: jsonEncode({
          'tag_name': 'v1.1.0',
          'body': 'Fresh fixes',
          'html_url': 'https://github.com/Zalweb/Tabby/releases/tag/v1.1.0',
          'assets': [],
        }),
      );
      final service = AppUpdateService(
        client: client,
        endpoint: Uri.parse('https://example.test/releases/latest'),
        installedVersionLoader: () async => const AppVersion(1, 0, 0, 1),
      );

      final update = await service.checkForUpdate();

      expect(update, isNotNull);
      expect(update!.release.version, const AppVersion(1, 1, 0));
      expect(client.lastRequest?.url.toString(),
          'https://example.test/releases/latest');
    });

    test('fails closed for HTTP errors and malformed JSON', () async {
      final service = AppUpdateService(
        client: _FakeHttpClient(statusCode: 503, body: 'unavailable'),
        installedVersionLoader: () async => const AppVersion(1, 0, 0),
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('does not report the installed release as an update', () async {
      final service = AppUpdateService(
        client: _FakeHttpClient(
          statusCode: 200,
          body: jsonEncode({
            'tag_name': 'v1.0.0',
            'html_url': 'https://example.test/release',
            'assets': [],
          }),
        ),
        installedVersionLoader: () async => const AppVersion(1, 0, 0, 1),
      );

      expect(await service.checkForUpdate(), isNull);
    });
  });

  testWidgets('shows the update dialog and allows the user to defer it',
      (tester) async {
    final release = AppUpdateRelease(
      version: const AppVersion(1, 1, 0, 2),
      releaseNotes: 'Fresh fixes',
      releaseUrl: Uri.parse('https://example.test/release'),
    );
    final checker = _FakeUpdateChecker(
      AppUpdateInfo(
        currentVersion: const AppVersion(1, 0, 0),
        release: release,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdatePrompt(
          checker: checker,
          child: const Scaffold(body: Text('Tabby')),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('A new version of Tabby is available'), findsOneWidget);
    expect(find.text('Version 1.1.0+2 is ready.'), findsOneWidget);
    expect(find.text('Update on Web'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('A new version of Tabby is available'), findsNothing);
    expect(checker.calls, 1);
  });

  testWidgets('does not check when the prompt is disabled', (tester) async {
    final checker = _FakeUpdateChecker(null);

    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdatePrompt(
          checker: checker,
          enabled: false,
          child: const Scaffold(body: Text('Tabby')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(checker.calls, 0);
  });

  testWidgets('shows the installed version and build number in the footer',
      (tester) async {
    final packageInfo = PackageInfo(
      appName: 'Tabby',
      packageName: 'com.zalweb.tabby',
      version: '1.0.1',
      buildNumber: '2',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppVersionFooter(
            packageInfoLoader: () async => packageInfo,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Version 1.0.1+2'), findsOneWidget);
  });
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
  http.Request? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request is http.Request ? request : null;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class _FakeUpdateChecker implements AppUpdateChecker {
  _FakeUpdateChecker(this.result);

  final AppUpdateInfo? result;
  int calls = 0;

  @override
  Future<AppUpdateInfo?> checkForUpdate() async {
    calls++;
    return result;
  }
}
