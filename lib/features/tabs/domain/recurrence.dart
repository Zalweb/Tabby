import 'package:timezone/timezone.dart' as tz;

enum RecurrenceUnit { daily, weekly, monthly }

/// Calendar-only anchor. No 24-hour/30-day approximation crosses DST/month-end.
class RecurrenceSchedule {
  RecurrenceSchedule({
    required this.anchor,
    required this.timeZone,
    required this.unit,
    this.step = 1,
  }) {
    if (anchor.hour != 0 ||
        anchor.minute != 0 ||
        anchor.second != 0 ||
        step < 1 ||
        step > 120 ||
        timeZone.isEmpty) {
      throw const FormatException(
        'Choose a calendar date, timezone and valid interval.',
      );
    }
  }
  final DateTime anchor;
  final String timeZone;
  final RecurrenceUnit unit;
  final int step;
  static DateTime date(String text) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      throw const FormatException('Enter YYYY-MM-DD.');
    }
    final value = DateTime.tryParse('${text}T00:00:00Z');
    if (value == null || value.toIso8601String().substring(0, 10) != text) {
      throw const FormatException('Enter a valid calendar date.');
    }
    return value;
  }

  static String label(DateTime value) =>
      value.toIso8601String().substring(0, 10);
  DateTime occurrence(int index) {
    if (index < 0 || index > 120000) {
      throw const FormatException('Invalid occurrence.');
    }
    if (unit != RecurrenceUnit.monthly) {
      return DateTime.utc(
        anchor.year,
        anchor.month,
        anchor.day + index * step * (unit == RecurrenceUnit.weekly ? 7 : 1),
      );
    }
    final month = DateTime.utc(anchor.year, anchor.month + index * step, 1);
    final last = DateTime.utc(month.year, month.month + 1, 0).day;
    return DateTime.utc(
      month.year,
      month.month,
      anchor.day < last ? anchor.day : last,
    );
  }

  DateTime dueUtc(int index, tz.Location location) {
    if (location.name != timeZone) {
      throw const FormatException('Timezone mismatch.');
    }
    final day = occurrence(index);
    return tz.TZDateTime(location, day.year, day.month, day.day).toUtc();
  }
}
