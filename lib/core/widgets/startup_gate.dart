import 'dart:async';

import '../../shared/widgets/tabby_loading_indicator.dart';

import 'package:flutter/material.dart';

import '../theme/tabby_palette.dart';
import '../theme/tabby_theme.dart';

import '../services/storage_recovery_service.dart';

/// Renders before initialization and keeps failed startup recoverable.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.initialize,
    required this.child,
    this.recovery,
    this.animateOpening = false,
  });
  final Future<List<String>> Function() initialize;
  final Widget child;
  final StorageRecoveryService? recovery;

  /// Opt-in bounded opening animation for production cold launches. Holds a
  /// clean, fast initialization for at most 400 ms (within the 420 ms budget)
  /// measured from the first rendered frame, while initialization runs
  /// concurrently. Errors, recoverable notices, retry, reduced motion and
  /// backgrounding yield immediately with no extra hold after the timer.
  /// Enabled by production `runApp` only; defaults to off.
  final bool animateOpening;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> with WidgetsBindingObserver {
  static const _openingRevealHold = Duration(milliseconds: 400);
  late Future<List<String>> _startup;
  bool _continued = false;
  bool _recovering = false, _restartRequired = false;
  String? _recoveryError;
  bool _revealActive = false;
  Timer? _revealTimer;
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
    WidgetsBinding.instance.addObserver(this);
    _startup = Future.sync(widget.initialize);
    if (widget.animateOpening &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations) {
      _revealActive = true;
      // Measure the bounded hold from the first rendered frame, not initState,
      // so an immediately-completing initialization still shows a brief visible
      // reveal. The timer never adds hold after it fires.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_revealActive) return;
        _revealTimer?.cancel();
        _revealTimer = Timer(_openingRevealHold, _endReveal);
      });
      // Real failures and recoverable notices never wait for the reveal.
      _startup.then((notices) {
        if (notices.isNotEmpty) _endReveal();
      }, onError: (Object _) => _endReveal());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _endReveal();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      _endReveal();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never extend startup while backgrounded.
    if (state != AppLifecycleState.resumed) _endReveal();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revealTimer?.cancel();
    super.dispose();
  }

  void _endReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (!_revealActive) return;
    if (mounted) {
      setState(() => _revealActive = false);
    } else {
      _revealActive = false;
    }
  }

  /// Brief mascot opening on the themed canvas, concurrent with real
  /// initialization. Reuses the startup loader so the same visible motion and
  /// pause/reduced-motion policies apply during the bounded reveal.
  Widget _buildOpeningReveal() {
    return MaterialApp(
      theme: TabbyTheme.lightTheme,
      darkTheme: TabbyTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) {
          final palette = TabbyPalette.of(context);
          return Scaffold(
            backgroundColor: palette.canvas,
            body: const SafeArea(
              child: Center(child: TabbyLoadingIndicator.startup()),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_continued) return widget.child;
    return FutureBuilder<List<String>>(
      future: _startup,
      builder: (context, snapshot) {
        final ready = snapshot.connectionState == ConnectionState.done;
        final storageFailure = snapshot.error is LocalStorageUnavailable;
        if (ready &&
            !snapshot.hasError &&
            snapshot.data!.isEmpty &&
            !_revealActive) {
          return widget.child;
        }
        // Errors and recoverable notices always yield immediately; the
        // opening reveal only holds a clean, fast launch.
        final hasProblem =
            ready && (snapshot.hasError || snapshot.data!.isNotEmpty);
        if (_revealActive && !hasProblem) {
          return _buildOpeningReveal();
        }
        return MaterialApp(
          theme: TabbyTheme.lightTheme,
          darkTheme: TabbyTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!ready) ...[
                            const TabbyLoadingIndicator.startup(),
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
                                        _startup = Future.sync(
                                          widget.initialize,
                                        );
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
                                onPressed: () =>
                                    setState(() => _continued = true),
                                child: const Text('Continue'),
                              ),
                          ],
                        ],
                      ),
                    ),
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
