import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/theme/motion_preferences.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/sync_diagnostics_provider.dart';

class SyncDiagnosticsSheet extends ConsumerWidget {
  const SyncDiagnosticsSheet({super.key, required this.hostContext});

  final BuildContext hostContext;

  static Future<void> show(BuildContext context) {
    unawaited(
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(syncDiagnosticsProvider.notifier).checkStatus(),
    );
    return showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
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
    final online = diagnostics.isOnline == true;
    final feedback =
        diagnostics.errorMessage ??
        (isBusy
            ? 'Tabby kept your cached data safe. Sync is in progress.'
            : null);

    return Material(
      color: TabbyPalette.of(context).surface,
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
                    Expanded(
                      child: Text(
                        'Backend & Offline Sync',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyPalette.of(context).text,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (isBusy ||
                    diagnostics.isOnline == false ||
                    diagnostics.status == SyncStatus.failed)
                  Center(
                    child: TabbyMascotWidget.art(
                      pose: isBusy
                          ? TabbyMascotPose.thinking
                          : TabbyMascotPose.helpful,
                      size: 64,
                    ),
                  ),
                const SizedBox(height: 14),
                _statusRow(
                  context,
                  icon: online ? Icons.cloud_done_rounded : Icons.cloud_off,
                  title: 'Network',
                  subtitle: online
                      ? 'A connection is available for server refreshes.'
                      : 'Cached tabs remain available until you reconnect.',
                  status: diagnostics.isOnline == null
                      ? 'Checking'
                      : online
                      ? 'Online'
                      : 'Offline',
                  color: online ? TabbyColors.brandAmber : TabbyColors.alertRed,
                ),
                const Divider(height: 24),
                Text(
                  '${diagnostics.pendingWrites} writes pending · ${diagnostics.needsAttention} need attention',
                ),
                if (diagnostics.needsAttention > 0)
                  TextButton(
                    onPressed: isBusy
                        ? null
                        : () async {
                            await ref
                                .read(syncDiagnosticsProvider.notifier)
                                .syncNow(retrySavedWrites: true);
                          },
                    child: const Text('Retry saved writes'),
                  ),
                _statusRow(
                  context,
                  icon: Icons.sync_rounded,
                  title: 'Server sync',
                  subtitle: diagnostics.lastSyncedAt == null
                      ? 'No successful refresh recorded in this session.'
                      : 'Last refreshed ${_formatTime(diagnostics.lastSyncedAt!)}.',
                  status: syncStatusLabel(diagnostics),
                  color: diagnostics.status == SyncStatus.failed
                      ? TabbyColors.alertRed
                      : TabbyColors.brandAmber,
                ),
                const Divider(height: 24),
                _statusRow(
                  context,
                  icon: Icons.phone_android_rounded,
                  title: 'Offline cache',
                  subtitle:
                      'Previously loaded tabs are protected on this device.',
                  status: 'Available',
                  color: TabbyColors.accentBurnt,
                ),
                if (feedback != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    feedback,
                    style: TextStyle(
                      color: TabbyPalette.of(context).secondaryText,
                      fontSize: 12,
                    ),
                  ),
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
                          TabbyFeedback.of(hostContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                synced
                                    ? ref
                                                  .read(syncDiagnosticsProvider)
                                                  .status ==
                                              SyncStatus.localOnly
                                          ? 'Saved on this device.'
                                          : 'All tabs and transactions are synchronized.'
                                    : ref
                                              .read(syncDiagnosticsProvider)
                                              .errorMessage ??
                                          'Your cached data is retained.',
                              ),
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

  Widget _statusRow(
    BuildContext context, {
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
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: TabbyPalette.of(context).secondaryText,
                  fontSize: 12,
                ),
              ),
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
