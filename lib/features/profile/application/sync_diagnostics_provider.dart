import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/supabase_config.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/sync_report.dart';
export '../../tabs/domain/sync_report.dart';

enum SyncStatus {
  checking,
  ready,
  offline,
  syncing,
  synchronized,
  pending,
  failed,
  localOnly
}

class SyncDiagnosticsState {
  const SyncDiagnosticsState(
      {this.status = SyncStatus.checking,
      this.lastSyncedAt,
      this.errorMessage,
      this.isOnline,
      this.pendingWrites = 0,
      this.needsAttention = 0});
  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final String? errorMessage;
  final bool? isOnline;
  final int pendingWrites;
  final int needsAttention;
  SyncDiagnosticsState copyWith(
          {SyncStatus? status,
          DateTime? lastSyncedAt,
          String? errorMessage,
          bool? isOnline,
          int? pendingWrites,
          int? needsAttention}) =>
      SyncDiagnosticsState(
          status: status ?? this.status,
          lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
          errorMessage: errorMessage,
          isOnline: isOnline ?? this.isOnline,
          pendingWrites: pendingWrites ?? this.pendingWrites,
          needsAttention: needsAttention ?? this.needsAttention);
}

abstract interface class ConnectivityProbe {
  Future<bool> isOnline();
}

class ConnectivityPlusProbe implements ConnectivityProbe {
  ConnectivityPlusProbe({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();
  final Connectivity _connectivity;
  @override
  Future<bool> isOnline() async => (await _connectivity.checkConnectivity())
      .any((result) => result != ConnectivityResult.none);
}

class SyncDiagnosticsNotifier extends StateNotifier<SyncDiagnosticsState> {
  SyncDiagnosticsNotifier(
      {ConnectivityProbe? probe,
      required this._sync,
      this._retryPending,
      this._pendingStatus,
      this.allowLocalModeSync = false})
      : _probe = probe ?? ConnectivityPlusProbe(),
        super(const SyncDiagnosticsState()) {
    unawaited(checkStatus());
  }
  final ConnectivityProbe _probe;
  final Future<SyncReport> Function() _sync;
  final Future<void> Function()? _retryPending;
  final Future<SyncReport> Function()? _pendingStatus;
  final bool allowLocalModeSync;
  int _generation = 0;
  bool _syncing = false;

  Future<void> checkStatus() async {
    if (!mounted || _syncing) return;
    final generation = ++_generation;
    try {
      final online = await _probe.isOnline();
      final pending = await _pendingStatus?.call();
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
          isOnline: online,
          pendingWrites: pending?.pendingWrites,
          needsAttention: pending?.needsAttention,
          status: !online
              ? SyncStatus.offline
              : (pending?.needsAttention ?? state.needsAttention) > 0
                  ? SyncStatus.failed
                  : (pending?.pendingWrites ?? state.pendingWrites) > 0
                      ? SyncStatus.pending
                      : state.status == SyncStatus.checking ||
                              state.status == SyncStatus.offline
                          ? SyncStatus.ready
                          : state.status,
          errorMessage: state.errorMessage);
    } catch (_) {
      if (mounted && generation == _generation) {
        state = state.copyWith(
            status: SyncStatus.failed,
            errorMessage:
                'Connection status is unavailable. Please try again.');
      }
    }
  }

  Future<bool> syncNow({bool retrySavedWrites = false}) async {
    if (!mounted || _syncing) return false;
    _syncing = true;
    ++_generation;
    state = state.copyWith(status: SyncStatus.syncing);
    try {
      final online = await _probe.isOnline();
      if (!mounted) return false;
      state = state.copyWith(isOnline: online, status: SyncStatus.syncing);
      if (!online && !(allowLocalModeSync && !SupabaseConfig.isInitialized)) {
        state = state.copyWith(
            status: SyncStatus.offline,
            errorMessage:
                'Your saved tabs remain available. Reconnect to sync.');
        return false;
      }
      if (retrySavedWrites && _retryPending != null) {
        await _retryPending();
      }
      final report = await _sync();
      if (!mounted) return false;
      final status = report.localSaved
          ? SyncStatus.localOnly
          : report.needsAttention > 0
              ? SyncStatus.failed
              : report.pendingWrites > 0
                  ? SyncStatus.pending
                  : report.synchronized
                      ? SyncStatus.synchronized
                      : SyncStatus.failed;
      state = state.copyWith(
          status: status,
          pendingWrites: report.pendingWrites,
          needsAttention: report.needsAttention,
          lastSyncedAt: report.synchronized ? DateTime.now() : null,
          errorMessage: report.synchronized || report.localSaved
              ? null
              : report.needsAttention > 0
                  ? 'Some saved writes need attention. Your cached data is retained.'
                  : report.pendingWrites > 0
                      ? 'Saved writes are waiting to sync.'
                      : 'The server refresh failed. Your cached data is retained.');
      return report.synchronized || report.localSaved;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
            status: SyncStatus.failed,
            errorMessage:
                'The refresh failed. Your cached data is retained. Please try again.');
      }
      return false;
    } finally {
      _syncing = false;
    }
  }
}

final syncDiagnosticsProvider =
    StateNotifierProvider<SyncDiagnosticsNotifier, SyncDiagnosticsState>(
        (ref) => SyncDiagnosticsNotifier(
            allowLocalModeSync: true,
            sync: () => ref.read(tabbyProvider.notifier).synchronize(),
            pendingStatus: () =>
                ref.read(tabbyProvider.notifier).pendingSyncReport(),
            retryPending: () =>
                ref.read(tabbyProvider.notifier).retryPendingWrites()));

String syncStatusLabel(SyncDiagnosticsState state) {
  if (!SupabaseConfig.isInitialized) return 'Local mode';
  return switch (state.status) {
    SyncStatus.checking => 'Checking',
    SyncStatus.ready => 'Ready to refresh',
    SyncStatus.offline => 'Offline',
    SyncStatus.syncing => 'Syncing',
    SyncStatus.synchronized => 'Synced',
    SyncStatus.pending => 'Writes pending',
    SyncStatus.failed => 'Needs attention',
    SyncStatus.localOnly => 'Local mode',
  };
}
