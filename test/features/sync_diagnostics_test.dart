import 'package:flutter_test/flutter_test.dart';

import 'package:tabby/features/profile/application/sync_diagnostics_provider.dart';

void main() {
  test('offline connectivity never reports synchronized', () async {
    final notifier = SyncDiagnosticsNotifier(
      probe: FakeConnectivityProbe(online: false),
      sync: () async => true,
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
      sync: () async => true,
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
