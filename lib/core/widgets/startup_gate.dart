import 'package:flutter/material.dart';

import '../theme/tabby_theme.dart';

import '../services/storage_recovery_service.dart';

/// Renders before initialization and keeps failed startup recoverable.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.initialize,
    required this.child,
    this.recovery,
  });
  final Future<List<String>> Function() initialize;
  final Widget child;
  final StorageRecoveryService? recovery;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<List<String>> _startup;
  bool _continued = false;
  bool _recovering = false, _restartRequired = false;
  String? _recoveryError;
  late final _recovery = widget.recovery ?? StorageRecoveryService();

  Future<void> _recover(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Recover local storage?'),
        content: const Text(
          'Tabby will preserve the encrypted local database and '
          'secure preferences privately on this device, then start fresh. '
          'Unsynced entries and drafts may remain unrecoverable without their '
          'original keys. They will not be sent automatically. Your shared '
          'online history is retained. Device authentication is required. '
          'You must close and reopen Tabby afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Preserve and reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _recovering = true;
      _recoveryError = null;
    });
    try {
      final recovered = await _recovery.preserveAndReset();
      if (mounted) setState(() => _restartRequired = recovered);
    } catch (_) {
      if (mounted) {
        setState(
          () => _recoveryError = 'Recovery did not finish. Existing recovery copies are retained. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _startup = Future.sync(widget.initialize);
  }

  @override
  Widget build(BuildContext context) {
    if (_continued) return widget.child;
    return FutureBuilder<List<String>>(
      future: _startup,
      builder: (context, snapshot) {
        final ready = snapshot.connectionState == ConnectionState.done;
        final storageFailure = snapshot.error is LocalStorageUnavailable;
        if (ready && !snapshot.hasError && snapshot.data!.isEmpty) {
          return widget.child;
        }
        return MaterialApp(
          theme: TabbyTheme.lightTheme,
          darkTheme: TabbyTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!ready) ...[
                        const CircularProgressIndicator(),
                        const Text('Starting Tabby…'),
                      ] else ...[
                        Text(
                          _restartRequired
                              ? 'Storage preserved. Close and reopen Tabby to continue.'
                              : storageFailure
                              ? 'Local storage could not be unlocked. Your existing data has not been erased. Unlock your device and try again, or recover local storage.'
                              : snapshot.hasError
                              ? 'Tabby couldn’t start. Please try again.'
                              : snapshot.data!.join('\n'),
                        ),
                        if (_recoveryError != null) Text(_recoveryError!),
                        if (_restartRequired)
                          FilledButton(
                            onPressed: _recovery.closeForRestart,
                            child: const Text('Close Tabby'),
                          )
                        else
                          FilledButton(
                            onPressed: _recovering
                                ? null
                                : () => setState(() {
                                    _startup = Future.sync(widget.initialize);
                                  }),
                            child: const Text('Try again'),
                          ),
                        if (!_restartRequired &&
                            storageFailure &&
                            (widget.recovery != null ||
                                StorageRecoveryService.supported))
                          Builder(
                            builder: (dialogContext) => TextButton(
                              onPressed: _recovering
                                  ? null
                                  : () => _recover(dialogContext),
                              child: const Text('Recover local storage'),
                            ),
                          ),
                        if (!snapshot.hasError)
                          TextButton(
                            onPressed: () => setState(() => _continued = true),
                            child: const Text('Continue'),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
