import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/tabby_colors.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();

class AppVersionFooter extends StatefulWidget {
  const AppVersionFooter({
    super.key,
    PackageInfoLoader? packageInfoLoader,
  }) : packageInfoLoader = packageInfoLoader ?? _loadPackageInfo;

  final PackageInfoLoader packageInfoLoader;

  static Future<PackageInfo> _loadPackageInfo() {
    return PackageInfo.fromPlatform();
  }

  @override
  State<AppVersionFooter> createState() => _AppVersionFooterState();
}

class _AppVersionFooterState extends State<AppVersionFooter> {
  late final Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = widget.packageInfoLoader();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final version = snapshot.hasData
            ? _formatVersion(snapshot.data!)
            : 'Version unavailable';
        return InkWell(
          onTap: () async {
            final uri = Uri.parse('https://tabby-web-fawn.vercel.app');
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              'Version $version',
              style: const TextStyle(
                fontSize: 11,
                color: TabbyColors.textSecondary,
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatVersion(PackageInfo packageInfo) {
    final version = packageInfo.version.trim();
    final buildNumber = packageInfo.buildNumber.trim();
    if (version.isEmpty) return 'unavailable';
    if (buildNumber.isEmpty || version.endsWith('+$buildNumber')) {
      return version;
    }
    return '$version+$buildNumber';
  }
}
