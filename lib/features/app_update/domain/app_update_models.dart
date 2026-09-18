class AppVersion {
  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  final int major;
  final int minor;
  final int patch;
  final int build;

  static AppVersion? tryParse(String? value, {String? buildNumber}) {
    if (value == null) return null;

    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(value.trim());
    if (match == null) return null;

    final embeddedBuild = int.tryParse(match.group(4) ?? '0');
    final explicitBuild = int.tryParse(buildNumber ?? '');
    if (embeddedBuild == null ||
        (buildNumber != null && explicitBuild == null)) {
      return null;
    }

    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      explicitBuild ?? embeddedBuild,
    );
  }

  String get displayValue => '$major.$minor.$patch';

  String get fullDisplayValue =>
      build > 0 ? '$displayValue+$build' : displayValue;

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  int compareTo(AppVersion other) {
    final semanticComparison = _compareParts(other);
    if (semanticComparison != 0) return semanticComparison;
    return build.compareTo(other.build);
  }

  int _compareParts(AppVersion other) {
    final majorComparison = major.compareTo(other.major);
    if (majorComparison != 0) return majorComparison;

    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) return minorComparison;

    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) {
    return other is AppVersion &&
        major == other.major &&
        minor == other.minor &&
        patch == other.patch &&
        build == other.build;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch, build);

  @override
  String toString() => '$displayValue+$build';
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.releaseNotes,
    required this.releaseUrl,
    this.androidDownloadUrl,
    this.iosDownloadUrl,
    this.webDownloadUrl,
  });

  final AppVersion version;
  final String releaseNotes;
  final Uri releaseUrl;
  final Uri? androidDownloadUrl;
  final Uri? iosDownloadUrl;
  final Uri? webDownloadUrl;

  static AppUpdateRelease? fromJson(Map<String, dynamic> json) {
    final rawTag = json['tag_name'];
    final rawReleaseUrl = json['html_url'];
    final version = rawTag is String ? AppVersion.tryParse(rawTag) : null;
    final releaseUrl =
        rawReleaseUrl is String ? _parseWebUri(rawReleaseUrl) : null;
    if (version == null || releaseUrl == null) return null;

    Uri? androidDownloadUrl;
    Uri? iosDownloadUrl;
    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;

        final name = asset['name'];
        final downloadUrl = asset['browser_download_url'];
        if (name is! String || downloadUrl is! String) continue;

        final uri = _parseWebUri(downloadUrl);
        if (uri == null) continue;

        final lowerName = name.toLowerCase();
        if (lowerName.endsWith('.apk')) {
          androidDownloadUrl ??= uri;
        } else if (lowerName.endsWith('.ipa')) {
          iosDownloadUrl ??= uri;
        }
      }
    }

    return AppUpdateRelease(
      version: version,
      releaseNotes:
          json['body'] is String ? (json['body'] as String).trim() : '',
      releaseUrl: releaseUrl,
      androidDownloadUrl: androidDownloadUrl,
      iosDownloadUrl: iosDownloadUrl,
      webDownloadUrl: Uri.parse('https://tabby-web-fawn.vercel.app/#download'),
    );
  }

  static Uri? _parseWebUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https') {
      return null;
    }
    if (uri.host.isEmpty) return null;
    return uri;
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.release,
  });

  final AppVersion currentVersion;
  final AppUpdateRelease release;
}

enum AppUpdateStatus { checking, upToDate, updateAvailable, unavailable }

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    this.update,
  });

  final AppUpdateStatus status;
  final AppUpdateInfo? update;
}

abstract interface class AppUpdateChecker {
  Future<AppUpdateInfo?> checkForUpdate();
}
