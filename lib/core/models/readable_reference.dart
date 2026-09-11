import 'dart:math';

/// Six unambiguous random characters (30 bits); document IDs remain internal.
String generateReference(String prefix, {DateTime? now, Random? random}) {
  final utc = (now ?? DateTime.now()).toUtc();
  // Trip dates use Asia/Colombo (UTC+05:30); support references retain UTC.
  final date = prefix == 'CT' ? utc.add(const Duration(hours: 5, minutes: 30)) : utc;
  final rng = random ?? Random.secure();
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  final day = '${(date.year % 100).toString().padLeft(2, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  final suffix = List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
  return '$prefix-$day-$suffix';
}
