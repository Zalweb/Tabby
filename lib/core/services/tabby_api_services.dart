import '../utils/philippine_phone.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Small helpers that used to lean on third-party web APIs.
///
/// Avatars, payment QR codes and email/phone checks now run entirely on the
/// device so no display name, account number or email address is sent to an
/// external service. The only remaining network call is an anonymous
/// PHP→USD rate lookup that carries no user data.
class TabbyApiServices {
  TabbyApiServices._();

  // ─────────────────────────────────────────────────────────────────────────
  // Email — local shape + disposable-domain check
  // ─────────────────────────────────────────────────────────────────────────

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  /// Common throwaway providers. Ownership of a real address is proven by
  /// Supabase Auth's confirmation email, so this list only catches the
  /// obvious signup-for-a-burner-address case.
  static const Set<String> _disposableDomains = {
    '10minutemail.com',
    'dispostable.com',
    'emailondeck.com',
    'fakeinbox.com',
    'getnada.com',
    'guerrillamail.com',
    'maildrop.cc',
    'mailinator.com',
    'mintemail.com',
    'mohmal.com',
    'sharklasers.com',
    'temp-mail.org',
    'tempmail.com',
    'throwawaymail.com',
    'trashmail.com',
    'yopmail.com',
  };

  /// Returns `true` when [email] has a plausible shape and does not use a
  /// known disposable domain.
  static bool isEmailAcceptable(String email) {
    final trimmed = email.trim().toLowerCase();
    if (!_emailPattern.hasMatch(trimmed)) return false;
    final domain = trimmed.split('@').last;
    return !_disposableDomains.contains(domain);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Philippine phone validation (offline)
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a friendly error string when the phone number is not a valid
  /// Philippine mobile number, or `null` when it is valid.
  ///
  /// Handles 09xx, +639xx, and 639xx formats.
  static String? validatePhilippinePhone(String phone) {
    final normalized = normalizePhilippineMobile(phone);
    if (normalized == null) {
      return 'Enter a valid Philippine mobile number (e.g. 09171234567 or +63 917 123 4567).';
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Currency-api (jsDelivr CDN) — PHP→USD rate with 24h in-memory cache
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
