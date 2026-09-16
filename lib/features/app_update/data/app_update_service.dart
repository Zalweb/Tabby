import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../domain/app_update_models.dart';

typedef InstalledVersionLoader = Future<AppVersion> Function();

class AppUpdateService implements AppUpdateChecker {
  AppUpdateService({
    http.Client? client,
    InstalledVersionLoader? installedVersionLoader,
    Uri? endpoint,
  })  : _client = client ?? http.Client(),
        _installedVersionLoader =
            installedVersionLoader ?? _loadInstalledVersion,
        _endpoint = endpoint ?? _latestReleaseEndpoint;

  static final Uri _latestReleaseEndpoint = Uri.parse(
    'https://api.github.com/repos/Zalweb/Tabby/releases/latest',
  );

  final http.Client _client;
  final InstalledVersionLoader _installedVersionLoader;
  final Uri _endpoint;

  @override
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final currentVersion = await _installedVersionLoader();
      final response = await _client.get(
        _endpoint,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Tabby-App',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      final release = AppUpdateRelease.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (release == null || !release.version.isNewerThan(currentVersion)) {
        return null;
      }

      return AppUpdateInfo(
        currentVersion: currentVersion,
        release: release,
      );
    } catch (_) {
      // An update check must never prevent the app from starting.
      return null;
    }
  }

  static Future<AppVersion> _loadInstalledVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = AppVersion.tryParse(
          packageInfo.version,
          buildNumber: packageInfo.buildNumber,
        ) ??
        AppVersion.tryParse(packageInfo.version);
    return version ?? const AppVersion(0, 0, 0);
  }
}
