import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_config.dart';
import '../../tabs/application/tabby_providers.dart';

enum SyncStatus { checking, offline, syncing, synchronized, failed }

class SyncDiagnosticsState {
  const SyncDiagnosticsState({
    this.status = SyncStatus.checking,
    this.lastSyncedAt,
    this.errorMessage,
  });

  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  SyncDiagnosticsState copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
    String? errorMessage,
  }) {
    return SyncDiagnosticsState(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: errorMessage,
    );
  }
}

abstract interface class ConnectivityProbe {
  Future<bool> isOnline();
}

class ConnectivityPlusProbe implements ConnectivityProbe {
  ConnectivityPlusProbe({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }
}

class SyncDiagnosticsNotifier extends StateNotifier<SyncDiagnosticsState> {
  SyncDiagnosticsNotifier({
    ConnectivityProbe? probe,
    required Future<bool> Function() sync,
    this.allowLocalModeSync = false,
  })  : _probe = probe ?? ConnectivityPlusProbe(),
        _sync = sync,
        super(const SyncDiagnosticsState()) {
    unawaited(checkStatus());
  }

  final ConnectivityProbe _probe;
  final Future<bool> Function() _sync;
  final bool allowLocalModeSync;

  Future<void> checkStatus() async {
    state = state.copyWith(status: SyncStatus.checking, errorMessage: null);
    final online = await _probe.isOnline();
    if (!mounted) return;
    state = state.copyWith(
      status: online ? SyncStatus.synchronized : SyncStatus.offline,
    );
  }

  Future<bool> syncNow() async {
    if (mounted) {
      state = state.copyWith(status: SyncStatus.syncing, errorMessage: null);
    }
    final online = await _probe.isOnline();
    if (!mounted) return false;
    if (!online) {
      if (allowLocalModeSync && !SupabaseConfig.isInitialized) {
        final localSaved = await _sync();
        if (mounted) {
          state = state.copyWith(
            status: localSaved ? SyncStatus.synchronized : SyncStatus.failed,
            lastSyncedAt: localSaved ? DateTime.now() : state.lastSyncedAt,
            errorMessage:
                localSaved
                    ? null
                    : 'Tabby kept your cached data safe. Sync will retry when you are online.',
          );
        }
        return localSaved;
      }
      state = state.copyWith(
        status: SyncStatus.offline,
        errorMessage:
            'Tabby kept your cached data safe. Sync will retry when you are online.',
      );
      return false;
    }

    final synced = await _sync();
    if (!mounted) return synced;
    state = state.copyWith(
      status: synced ? SyncStatus.synchronized : SyncStatus.failed,
      lastSyncedAt: synced ? DateTime.now() : state.lastSyncedAt,
      errorMessage: synced
          ? null
          : 'Tabby kept your cached data safe. The server refresh will retry.',
    );
    return synced;
  }
}

final syncDiagnosticsProvider =
    StateNotifierProvider<SyncDiagnosticsNotifier, SyncDiagnosticsState>(
  (ref) => SyncDiagnosticsNotifier(
    allowLocalModeSync: true,
    sync: () => ref.read(tabbyProvider.notifier).refreshTabs(),
  ),
);

String syncStatusLabel(SyncDiagnosticsState state) {
  if (!SupabaseConfig.isInitialized) return 'Local mode';
  return switch (state.status) {
    SyncStatus.checking => 'Checking',
    SyncStatus.offline => 'Offline',
    SyncStatus.syncing => 'Syncing',
    SyncStatus.synchronized => 'Synced',
    SyncStatus.failed => 'Needs attention',
  };
}
