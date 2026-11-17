import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/theme/motion_preferences.dart';
import 'package:flutter/material.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../../../core/services/receiving_qr_export.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../domain/payment_method.dart';

/// One automatic refresh for a failed URL, then an explicit retry. A fresh
/// server read must still authorize the method before issuing another URL.
class ReceivingQrImage extends StatefulWidget {
  const ReceivingQrImage(
      {super.key,
      required this.method,
      required this.reload,
      this.captureSession,
      this.sessionIsCurrent,
      this.fullscreen = false});
  final PaymentMethod method;
  final Future<PaymentMethod?> Function() reload;
  final SessionStamp Function()? captureSession;
  final bool Function(SessionStamp)? sessionIsCurrent;
  final bool fullscreen;
  @override
  State<ReceivingQrImage> createState() => _ReceivingQrImageState();
}

class _ReceivingQrImageState extends State<ReceivingQrImage> {
  late final SessionStamp _session;
  bool get _current => mounted &&
      (widget.sessionIsCurrent ?? SupabaseConfig.isCurrentSession)(_session);
  late PaymentMethod? _method = widget.method;
  bool _automaticTried = false;
  bool _busy = false;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _session = (widget.captureSession ?? SupabaseConfig.captureSession)();
    SupabaseConfig.sessionRevision.addListener(_sessionChanged);
  }
  void _sessionChanged() {
    if (_current) return;
    ++_request;
    setState(() { _method = null; _busy = false; _failed = true; });
  }
  @override
  void dispose() {
    SupabaseConfig.sessionRevision.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReceivingQrImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_current && oldWidget.method != widget.method) {
      if (oldWidget.method.id != widget.method.id ||
          oldWidget.method.qrStoragePath != widget.method.qrStoragePath ||
          oldWidget.method.revision != widget.method.revision) {
        _automaticTried = false;
      }
      _method = widget.method;
      _failed = false;
    }
  }

  void _imageFailed() {
    if (!_current || _automaticTried || _busy) return;
    _automaticTried = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    if (!_current || _busy) return;
    final request = ++_request;
    final session = (widget.captureSession ?? SupabaseConfig.captureSession)();
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final fresh = await widget.reload();
      if (!mounted || request != _request) return;
      final current =
          (widget.sessionIsCurrent ?? SupabaseConfig.isCurrentSession)(session);
      setState(() {
        _method = current ? fresh : null;
        _failed = !current;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _method = null;
          _failed = true;
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  void _openFullscreen() {
    final method = _method;
    if (!_current || method == null) return;
    showDialog<void>(
        animationStyle: TabbyMotion.style(context),
        context: context,
        useSafeArea: false,
        builder: (_) => AccountDraftGuard(child: Dialog.fullscreen(
            child: Scaffold(
                appBar: AppBar(title: const Text('Receiving QR')),
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ReceivingQrImage(
                        method: method,
                        reload: widget.reload,
                        fullscreen: true,
                        captureSession: widget.captureSession,
                        sessionIsCurrent: widget.sessionIsCurrent))))));
  }

  Future<void> _export(bool share) async {
    final method = _method;
    if (!_current || method == null || _busy) return;
    final session = SupabaseConfig.captureSession();
    setState(() => _busy = true);
    try {
      final saved = await ReceivingQrExport.export(
          share: share,
          download: () =>
              SupabaseTabbyRepository.instance.downloadReceivingQr(method.id));
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
      TabbyFeedback.of(context).showSnackBar(SnackBar(
          content: Text(share
              ? 'Choose an app to share this QR.'
              : (saved
                  ? 'QR image saved. Import it in your wallet to pay.'
                  : 'QR save cancelled.'))));
    } catch (_) {
      if (mounted && SupabaseConfig.isCurrentSession(session)) {
        TabbyFeedback.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not export this QR. Refresh it and try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _retry() => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_failed
            ? 'Could not refresh this receiving QR.'
            : 'Receiving QR unavailable.'),
        TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry QR')),
      ]);

  @override
  Widget build(BuildContext context) {
    if (!_current) return const Text('Receiving QR unavailable. Reopen receiving methods.');
    if (_busy) {
      return const SizedBox(
          height: 190, child: Center(child: CircularProgressIndicator()));
    }
    final method = _method;
    if (method == null || !method.isActive) return _retry();
    if (method.qrUrl == null) {
      if (method.qrStoragePath != null || _failed) {
        _imageFailed();
        return _retry();
      }
      return Text(method.accountLabel.isEmpty
          ? 'No receiving QR saved.'
          : 'Manual account details: ${method.accountLabel}');
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(method.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: SizedBox(
              width: widget.fullscreen
                  ? MediaQuery.sizeOf(context).width - 32
                  : 240,
              height: widget.fullscreen
                  ? MediaQuery.sizeOf(context).width - 32
                  : 240,
              child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.network(
                        method.qrUrl!,
                        key: ValueKey(method.qrUrl),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) {
                          _imageFailed();
                          return _retry();
                        },
                      ))))),
      Wrap(alignment: WrapAlignment.center, children: [
        if (!widget.fullscreen)
          TextButton.icon(
              onPressed: _openFullscreen,
              icon: const Icon(Icons.fullscreen),
              label: const Text('Fullscreen QR')),
        if (ReceivingQrExport.supported) ...[
          TextButton.icon(
              onPressed: () => _export(false),
              icon: const Icon(Icons.download),
              label: const Text('Save QR image')),
          TextButton.icon(
              onPressed: () => _export(true),
              icon: const Icon(Icons.share),
              label: const Text('Share QR image')),
        ],
      ]),
      const Text('Pay in your wallet, then submit payment separately.',
          textAlign: TextAlign.center),
    ]);
  }
}
