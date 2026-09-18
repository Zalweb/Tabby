import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/sync_diagnostics_provider.dart';

class SyncDiagnosticsSheet extends ConsumerWidget {
  const SyncDiagnosticsSheet({super.key, required this.hostContext});

  final BuildContext hostContext;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SyncDiagnosticsSheet(hostContext: context),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(syncDiagnosticsProvider);
    final isBusy = diagnostics.status == SyncStatus.syncing;
    final online = diagnostics.status != SyncStatus.offline;
    final feedback = diagnostics.errorMessage ??
        (isBusy
            ? 'Tabby kept your cached data safe. Sync is in progress.'
            : null);

    return Material(
      color: TabbyColors.surfaceWhite,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Backend & Offline Sync',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.brandDarkTeal)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _statusRow(
                  icon: online ? Icons.cloud_done_rounded : Icons.cloud_off,
                  title: 'Network',
                  subtitle: online
                      ? 'A connection is available for server refreshes.'
                      : 'Cached tabs remain available until you reconnect.',
                  status: online ? 'Online' : 'Offline',
                  color:
                      online ? TabbyColors.brandEmerald : TabbyColors.alertRed,
                ),
                const Divider(height: 24),
                _statusRow(
                  icon: Icons.sync_rounded,
                  title: 'Server sync',
                  subtitle: diagnostics.lastSyncedAt == null
                      ? 'No successful refresh recorded in this session.'
                      : 'Last refreshed ${_formatTime(diagnostics.lastSyncedAt!)}.',
                  status: syncStatusLabel(diagnostics),
                  color: diagnostics.status == SyncStatus.failed
                      ? TabbyColors.alertRed
                      : TabbyColors.brandEmerald,
                ),
                const Divider(height: 24),
                _statusRow(
                  icon: Icons.phone_android_rounded,
                  title: 'Offline cache',
                  subtitle:
                      'Previously loaded tabs are protected on this device.',
                  status: 'Available',
                  color: TabbyColors.accentBlue,
                ),
                if (feedback != null) ...[
                  const SizedBox(height: 12),
                  Text(feedback,
                      style: const TextStyle(
                          color: TabbyColors.alertRed, fontSize: 12)),
                ],
                const SizedBox(height: 22),
                TabbyButton(
                  label: isBusy ? 'Syncing...' : 'Sync Data Now',
                  onPressed: isBusy
                      ? null
                      : () async {
                          final synced = await ref
                              .read(syncDiagnosticsProvider.notifier)
                              .syncNow();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(hostContext).showSnackBar(
                            SnackBar(
                              content: Text(synced
                                  ? 'All tabs and transactions are fully synchronized.'
                                  : 'Tabby kept your cached data safe. Sync will retry when you are online.'),
                              backgroundColor: synced
                                  ? TabbyColors.brandEmerald
                                  : TabbyColors.alertRed,
                            ),
                          );
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String status,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text(status,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: const TextStyle(
                      color: TabbyColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.hour}:$minute';
  }
}
