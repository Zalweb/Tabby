/// Philippine mobile structure only. This never verifies subscriber ownership,
/// carrier assignment or whether a phone number is a wallet account.
String? normalizePhilippineMobile(String input) {
  final raw = input.trim();
  if (raw.isEmpty || !RegExp(r'^\+?[0-9 ()-]+$').hasMatch(raw)) return null;
  final compact = raw.replaceAll(RegExp(r'[ ()-]'), '');
  if (RegExp(r'^09[0-9]{9}$').hasMatch(compact)) {
    return '+63${compact.substring(1)}';
  }
  if (RegExp(r'^9[0-9]{9}$').hasMatch(compact)) return '+63$compact';
  if (RegExp(r'^\+?639[0-9]{9}$').hasMatch(compact)) {
    return compact.startsWith('+') ? compact : '+$compact';
  }
  return null;
}
