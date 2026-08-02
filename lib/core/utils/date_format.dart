import 'package:intl/intl.dart';

String relativeTime(DateTime? time) {
  if (time == null) return 'Never';
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  final d = diff.inDays;
  return '$d day${d == 1 ? '' : 's'} ago';
}

/// Absolute post date for share-card meta lines, e.g. "Aug 2, 2026" --
/// unlike [relativeTime], this doesn't change as time passes after the
/// card is shared.
String postDate(DateTime time) => DateFormat('MMM d, y').format(time);
