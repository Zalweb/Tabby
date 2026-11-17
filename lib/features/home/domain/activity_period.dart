import '../../tabs/domain/models.dart';

enum ActivityPeriod {
  last24Hours('Last 24h'),
  last7Days('Last 7 days'),
  thisMonth('This month');

  const ActivityPeriod(this.label);
  final String label;

  /// Rolling windows include both boundaries and exclude future timestamps.
  /// Calendar month follows the device's local calendar, including UTC rows.
  bool includes(DateTime timestamp, DateTime now) {
    final local = now.toLocal();
    final start = switch (this) {
      last24Hours => now.subtract(const Duration(hours: 24)),
      last7Days => now.subtract(const Duration(days: 7)),
      thisMonth => DateTime(local.year, local.month, 1),
    };
    return !timestamp.isBefore(start) && !timestamp.isAfter(now);
  }
}

List<TabbyActivity> activitiesForPeriod(
  Iterable<TabbyActivity> activities,
  ActivityPeriod period,
  DateTime now,
) {
  return activities
      .where((activity) => period.includes(activity.timestamp, now))
      .toList()
    ..sort((a, b) {
      final time = b.timestamp.compareTo(a.timestamp);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
}
