import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/features/profile/application/sync_diagnostics_provider.dart';

void main() {
  test('online connectivity alone never claims server synchronization',
      () async {
    final notifier = SyncDiagnosticsNotifier(
        probe: FakeConnectivityProbe(online: true),
        sync: () async => const SyncReport(serverRefreshed: false));
    addTearDown(notifier.dispose);
    await notifier.checkStatus();
    expect(notifier.state.status, SyncStatus.ready);
    expect(notifier.state.lastSyncedAt, isNull);
    expect(await notifier.syncNow(), isFalse);
    expect(notifier.state.status, SyncStatus.failed);
  });
  test(
      'failed refresh preserves the last successful timestamp and failure state',
      () async {
    var succeeds = true;
    final notifier = SyncDiagnosticsNotifier(
        probe: FakeConnectivityProbe(online: true),
        sync: () async => SyncReport(serverRefreshed: succeeds));
    addTearDown(notifier.dispose);
    expect(await notifier.syncNow(), isTrue);
    final previous = notifier.state.lastSyncedAt;
    succeeds = false;
    expect(await notifier.syncNow(), isFalse);
    await notifier.checkStatus();
    expect(notifier.state.status, SyncStatus.failed);
    expect(notifier.state.lastSyncedAt, previous);
  });
  test('pending or attention writes prevent a synchronized result', () async {
    final notifier = SyncDiagnosticsNotifier(
        probe: FakeConnectivityProbe(online: true),
        sync: () async => const SyncReport(
            serverRefreshed: true, pendingWrites: 2, needsAttention: 1));
    addTearDown(notifier.dispose);
    expect(await notifier.syncNow(), isFalse);
    expect(notifier.state.pendingWrites, 2);
    expect(notifier.state.needsAttention, 1);
    expect(notifier.state.lastSyncedAt, isNull);
  });
  test(
      'exceptions become actionable failure instead of escaping or claiming success',
      () async {
    final notifier = SyncDiagnosticsNotifier(
        probe: FakeConnectivityProbe(online: true),
        sync: () async => throw StateError('Server failed'));
    addTearDown(notifier.dispose);
    expect(await notifier.syncNow(), isFalse);
    expect(notifier.state.status, SyncStatus.failed);
    expect(notifier.state.errorMessage, contains('cached data is retained'));
  });
  test('local cache save is distinct from server synchronization', () async {
    final notifier = SyncDiagnosticsNotifier(
        probe: FakeConnectivityProbe(online: false),
        allowLocalModeSync: true,
        sync: () async =>
            const SyncReport(serverRefreshed: false, localSaved: true));
    addTearDown(notifier.dispose);
    expect(await notifier.syncNow(), isTrue);
    expect(notifier.state.status, SyncStatus.localOnly);
    expect(notifier.state.lastSyncedAt, isNull);
  });
  test(
      'concurrent sync requests run one executor and stale probes cannot overwrite it',
      () async {
    final complete = Completer<SyncReport>();
    var calls = 0;
    final notifier = SyncDiagnosticsNotifier(
        probe: FakeConnectivityProbe(online: true),
        sync: () {
          calls++;
          return complete.future;
        });
    addTearDown(notifier.dispose);
    final first = notifier.syncNow();
    await Future<void>.delayed(Duration.zero);
    expect(await notifier.syncNow(), isFalse);
    expect(calls, 1);
    complete.complete(const SyncReport(serverRefreshed: true));
    expect(await first, isTrue);
    expect(notifier.state.status, SyncStatus.synchronized);
  });
  test('offline connectivity never reports synchronized', () async {
    final notifier = SyncDiagnosticsNotifier(
      probe: FakeConnectivityProbe(online: false),
      sync: () async => const SyncReport(serverRefreshed: true),
    );

    await notifier.checkStatus();

    expect(notifier.state.status, SyncStatus.offline);
    expect(await notifier.syncNow(), isFalse);
    expect(notifier.state.status, SyncStatus.offline);
    notifier.dispose();
  });

  test('synchronization is reported only after the server callback succeeds',
      () async {
    final notifier = SyncDiagnosticsNotifier(
      probe: FakeConnectivityProbe(online: true),
      sync: () async => const SyncReport(serverRefreshed: true),
    );

    expect(await notifier.syncNow(), isTrue);
    expect(notifier.state.status, SyncStatus.synchronized);
    expect(notifier.state.lastSyncedAt, isNotNull);
    notifier.dispose();
  });
}

class FakeConnectivityProbe implements ConnectivityProbe {
  FakeConnectivityProbe({required this.online});

  final bool online;

  @override
  Future<bool> isOnline() async => online;
}
