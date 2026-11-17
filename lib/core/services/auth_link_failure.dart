import 'package:supabase_flutter/supabase_flutter.dart';

bool isAuthLinkFailure(Object error) {
  if (error is AuthPKCEGrantCodeExchangeError) return true;
  if (error is! AuthException) return false;
  const codes = {
    'otp_expired',
    'flow_state_not_found',
    'flow_state_expired',
    'bad_code_verifier',
    'validation_failed',
    'access_denied'
  };
  // The installed SDK places URL error_code in statusCode and URL error in code.
  return codes.contains(error.code) || codes.contains(error.statusCode);
}
