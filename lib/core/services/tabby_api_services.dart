import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sprint 1 — APIVault integrations for Tabby.
///
/// Five lightweight API clients, all fail-open so no API error ever blocks the user.
/// No new pub.dev packages — uses the `http: ^1.2.2` that is already in pubspec.yaml.
///
/// APIs used:
///  1. DiceBear  — deterministic initials avatar SVG (no key required)
///  2. GoQR.me   — QR code PNG generation (no key required)
///  3. Disify    — disposable email detection (no key required, 1 req/s)
///  4. Veriphone — Philippine phone validation (offline regex by default)
///  5. Currency-api (jsDelivr CDN) — PHP→USD rate, 24h cached (no key)
class TabbyApiServices {
  TabbyApiServices._();

  // ─────────────────────────────────────────────────────────────────────────
  // 1. DiceBear — deterministic initials avatar
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a DiceBear `initials` SVG URL seeded by [displayName].
  ///
  /// The resulting URL can be passed directly to [Image.network].
  /// Colors match Tabby brand: Emerald (#1b998b bg, white text).
  static String dicebearUrl(String displayName) {
    final name = displayName.trim().isEmpty ? 'T' : displayName.trim();
    final seed = Uri.encodeComponent(name);
    return 'https://api.dicebear.com/7.x/initials/svg'
        '?seed=$seed'
        '&backgroundColor=1b998b'
        '&textColor=ffffff'
        '&fontSize=42'
        '&fontWeight=700';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. GoQR.me — QR code generation
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a GoQR.me PNG URL that encodes [data] as a QR code.
  ///
  /// [size] sets both width and height in pixels (default 300).
  /// The resulting URL is a direct image URL usable in [Image.network].
  static String goQrUrl(String data, {int size = 300}) {
    final encoded = Uri.encodeComponent(data.trim());
    return 'https://api.qrserver.com/v1/create-qr-code/'
        '?data=$encoded'
        '&size=${size}x$size'
        '&margin=10'
        '&format=png';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Disify — disposable / invalid email detection
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns `true` when the email is safe to accept (real format, not disposable).
  /// Returns `true` on any network error so the user is never blocked by an API failure.
  static Future<bool> isEmailAllowed(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    try {
      final uri = Uri.parse(
        'https://www.disify.com/api/email/${Uri.encodeComponent(trimmed)}',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return true; // fail open
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final format = json['format'] as bool? ?? true;
      final disposable = json['disposable'] as bool? ?? false;
      return format && !disposable;
    } catch (e) {
      debugPrint('[TabbyApiServices] Disify check skipped (fail open): $e');
      return true;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Philippine phone validation (offline regex; Veriphone-ready)
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a friendly error string when the phone number is not a valid
  /// Philippine mobile number, or `null` when it is valid.
  ///
  /// Offline regex handles 09xx, +639xx, and 639xx formats.
  /// Pass a non-empty [apiKey] to additionally call Veriphone for carrier/type
  /// validation (1,000 free checks/month at veriphone.io).
  static Future<String?> validatePhilippinePhone(
    String phone, {
    String? apiKey,
  }) async {
    final normalized = _normalizePHPhone(phone.replaceAll(RegExp(r'\D'), ''));
    if (normalized == null) {
      return 'Enter a valid Philippine mobile number (e.g. 09171234567 or +63 917 123 4567).';
    }

    // Offline regex passed — skip API if no key provided.
    if (apiKey == null || apiKey.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://api.veriphone.io/v2/verify'
        '?phone=${Uri.encodeComponent(normalized)}'
        '&key=$apiKey',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null; // fail open
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final valid = json['phone_valid'] as bool? ?? true;
      final type = (json['phone_type'] as String? ?? '').toLowerCase();
      final country = (json['country_code'] as String? ?? '').toUpperCase();
      if (!valid) {
        return 'That number does not appear to be active. Double-check it.';
      }
      if (country.isNotEmpty && country != 'PH') {
        return 'Please enter a Philippine number (+63).';
      }
      if (type == 'landline' || type == 'fixed_line') {
        return 'GCash and Maya only work with mobile numbers, not landlines.';
      }
      return null;
    } catch (e) {
      debugPrint('[TabbyApiServices] Veriphone check skipped (fail open): $e');
      return null;
    }
  }

  /// Normalises a raw digit string to E.164 PH format (+639XXXXXXXXX),
  /// or returns null when the number does not match PH mobile patterns.
  static String? _normalizePHPhone(String digits) {
    String d = digits;
    // Strip country code prefixes
    if (d.startsWith('63') && d.length == 12) d = d.substring(2);
    if (d.startsWith('0') && d.length == 11) d = d.substring(1);
    // PH mobile subscribers start with 9 and have 10 digits
    if (d.length == 10 && d.startsWith('9')) return '+63$d';
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 5. Currency-api (jsDelivr CDN) — PHP→USD rate with 24h in-memory cache
  // ─────────────────────────────────────────────────────────────────────────

  static double? _cachedPhpToUsdRate;
  static DateTime? _cacheTimestamp;

  /// Fetches the live PHP→USD exchange rate, caching it for 24 hours.
  /// Returns `null` on failure so callers can hide the USD line gracefully.
  static Future<double?> getPhpToUsdRate() async {
    final now = DateTime.now();
    if (_cachedPhpToUsdRate != null &&
        _cacheTimestamp != null &&
        now.difference(_cacheTimestamp!).inHours < 24) {
      return _cachedPhpToUsdRate;
    }
    try {
      const url =
          'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest'
          '/v1/currencies/php.json';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return _cachedPhpToUsdRate;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final phpRates = json['php'] as Map<String, dynamic>?;
      final usdRate = (phpRates?['usd'] as num?)?.toDouble();
      if (usdRate != null) {
        _cachedPhpToUsdRate = usdRate;
        _cacheTimestamp = now;
      }
      return usdRate;
    } catch (e) {
      debugPrint('[TabbyApiServices] Currency-api error: $e');
      return _cachedPhpToUsdRate; // serve stale cache rather than null
    }
  }

  /// Converts [centavos] to a display string like `'≈ $12.34 USD'`,
  /// or returns `null` when the rate is unavailable.
  static Future<String?> centavosToUsdDisplay(int centavos) async {
    if (centavos == 0) return null;
    final rate = await getPhpToUsdRate();
    if (rate == null) return null;
    final usd = (centavos / 100.0) * rate;
    return '≈ \$${usd.toStringAsFixed(2)} USD';
  }

  /// Clears the cached rate (useful in tests).
  static void clearRateCache() {
    _cachedPhpToUsdRate = null;
    _cacheTimestamp = null;
  }
}
