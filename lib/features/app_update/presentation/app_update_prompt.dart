import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_update_service.dart';
import '../domain/app_update_models.dart';

class AppUpdatePrompt extends StatefulWidget {
  AppUpdatePrompt({
    super.key,
    required this.child,
    AppUpdateChecker? checker,
    this.enabled = true,
    this.navigatorKey,
  }) : checker = checker ?? AppUpdateService();

  final Widget child;
  final AppUpdateChecker checker;
  final bool enabled;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends State<AppUpdatePrompt> {
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_checkForUpdate());
      });
    }
  }

  Future<void> _checkForUpdate() async {
    if (_hasChecked || !mounted) return;
    _hasChecked = true;

    AppUpdateInfo? update;
    try {
      update = await widget.checker.checkForUpdate();
    } catch (_) {
      return;
    }
    if (!mounted || update == null) return;
    final availableUpdate = update;

    await showDialog<void>(
      context: widget.navigatorKey?.currentContext ?? context,
      barrierDismissible: true,
      builder: (context) => _UpdateDialog(update: availableUpdate),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.update});

  final AppUpdateInfo update;

  @override
  Widget build(BuildContext context) {
    final release = update.release;
    return AlertDialog(
      title: const Text('A new version of Tabby is available'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${release.version.displayValue} is ready.'),
            if (release.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'What is new',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(release.releaseNotes),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => _openUpdate(context, release),
          child: const Text('View update'),
        ),
      ],
    );
  }

  Future<void> _openUpdate(
    BuildContext context,
    AppUpdateRelease release,
  ) async {
    final updateUrl = _updateUrlForPlatform(release);
    Navigator.of(context).pop();
    try {
      await launchUrl(updateUrl, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('[AppUpdate] Could not open update URL: $error');
    }
  }

  Uri _updateUrlForPlatform(AppUpdateRelease release) {
    if (defaultTargetPlatform == TargetPlatform.android &&
        release.androidDownloadUrl != null) {
      return release.androidDownloadUrl!;
    }
    return release.releaseUrl;
  }
}
