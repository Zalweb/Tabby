/// Retains cold-start taps until authentication/router startup, then authorizes
/// the target against the current account. Never trusts a route from a payload.
class NotificationTapCoordinator {
  NotificationTapCoordinator({
    required this.canOpenTab,
    required this.prepareTab,
    required this.navigate,
  });
  final Future<bool> Function(String actor, String tab) canOpenTab;
  final Future<bool> Function(String actor, String tab) prepareTab;
  final void Function(String route) navigate;
  Map<String, dynamic>? _pending;
  bool _busy = false;
  int _version = 0;
  void receive(Map<String, dynamic> payload) {
    _pending = payload;
    _version++;
  }

  Future<void> flush({
    required String? actor,
    required bool Function() current,
  }) async {
    if (_busy || actor == null || _pending == null) return;
    _busy = true;
    final payload = _pending!, version = _version;
    try {
      if (payload['account'] != actor) {
        if (version == _version) _pending = null;
        return;
      }
      final route = payload['route'];
      String? target;
      if (route == 'connections') {
        target = '/profile/connections';
      } else if (route is String && route.startsWith('tab:')) {
        final tab = route.substring(4);
        if (RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ).hasMatch(tab) &&
            await canOpenTab(actor, tab)) {
          if (!current() || version != _version) return;
          // Membership does not mean the dashboard has loaded this tab yet.
          // Keep the tap pending if a scoped refresh cannot prepare its model.
          if (!await prepareTab(actor, tab)) return;
          target = '/tabs/$tab';
        }
      }
      if (version == _version) _pending = null;
      if (target != null && current() && version == _version) navigate(target);
    } catch (_) {
      // Keep a transient authorization read failure pending for the next resume.
      if (version == _version) _pending = payload;
    } finally {
      _busy = false;
      if (version != _version && current()) {
        await flush(actor: actor, current: current);
      }
    }
  }
}
