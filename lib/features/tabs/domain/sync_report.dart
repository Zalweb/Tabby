class SyncReport {
  const SyncReport(
      {required this.serverRefreshed,
      this.localSaved = false,
      this.pendingWrites = 0,
      this.needsAttention = 0});
  final bool serverRefreshed;
  final bool localSaved;
  final int pendingWrites;
  final int needsAttention;
  bool get synchronized =>
      serverRefreshed && pendingWrites == 0 && needsAttention == 0;
}
