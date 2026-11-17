/// Allocates each centavo once in immutable ID order, independent of payer,
/// viewer or backend row order.
Map<String, int> allocateEqualShares(
    int total, Iterable<String> participantIds) {
  if (total < 0) {
    throw ArgumentError.value(total, 'total', 'must not be negative');
  }
  final ids = participantIds.toSet().toList()..sort();
  if (ids.isEmpty) return const {};
  final base = total ~/ ids.length;
  final remainder = total % ids.length;
  return {
    for (var i = 0; i < ids.length; i++) ids[i]: base + (i < remainder ? 1 : 0)
  };
}
