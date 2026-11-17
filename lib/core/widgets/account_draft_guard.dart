import 'package:flutter/material.dart';
import '../config/session_scope.dart';
import '../config/supabase_config.dart';

/// Dismiss this exact draft route on logout/relogin, including when another
/// sheet is above it. Never pop a different account's replacement route.
class AccountDraftGuard extends StatefulWidget {
  const AccountDraftGuard({super.key, required this.child});
  final Widget child;
  @override
  State<AccountDraftGuard> createState() => _AccountDraftGuardState();
}

class _AccountDraftGuardState extends State<AccountDraftGuard> {
  late final SessionStamp _session;
  bool _expired = false;
  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.captureSession();
    SupabaseConfig.sessionRevision.addListener(_changed);
  }

  void _changed() {
    if (_expired || SupabaseConfig.isCurrentSession(_session)) return;
    setState(() => _expired = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.isActive == true) Navigator.of(context).removeRoute(route!);
    });
  }

  @override
  void dispose() {
    SupabaseConfig.sessionRevision.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _expired ? const SizedBox.shrink() : widget.child;
}
