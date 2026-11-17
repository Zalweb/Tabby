import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class AuthMutationContext {
  const AuthMutationContext(
      {required this.account,
      required this.accessToken,
      required this.endpoint,
      required this.headers,
      required this.current});
  final String account, accessToken;
  final Uri endpoint;
  final Map<String, String> headers;
  final bool Function() current;
}

/// Auth's updateUser mutates the shared SDK session after its HTTP await.
/// This transport deliberately never installs its response into that session.
class AuthUserMutation {
  AuthUserMutation(
      {required this.capture,
      required this.pkceStorage,
      required this.client,
      this.timeout = const Duration(seconds: 20)});
  static final instance = AuthUserMutation(
      capture: () {
        if (!SupabaseConfig.isInitialized) return null;
        final stamp = SupabaseConfig.captureSession(),
            session = SupabaseConfig.auth.currentSession;
        if (session == null) return null;
        return AuthMutationContext(
            account: session.user.id,
            accessToken: session.accessToken,
            endpoint: SupabaseConfig.authUserEndpoint,
            headers: Map<String, String>.from(SupabaseConfig.auth.headers),
            current: () => SupabaseConfig.isCurrentSession(stamp));
      },
      pkceStorage: _LazyPkceStorage(),
      client: http.Client());

  // Installed GoTrue2.27.2's default verifier namespace. Keeping the same public
  // storage adapter also preserves existing SDK recovery/OAuth/link exchange.
  static const verifierKey = 'supabase.auth.token-code-verifier';
  final AuthMutationContext? Function() capture;
  final GotrueAsyncStorage pkceStorage;
  final http.Client client;
  final Duration timeout;
  bool _busy = false;

  static String? tokenSubject(String token) {
    try {
      final claims = jsonDecode(utf8.decode(
          base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map;
      final subject = claims['sub'];
      return subject is String && subject.isNotEmpty ? subject : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateEmail(String email, {required String redirectTo}) =>
      _update(email: email, redirectTo: redirectTo);
  Future<void> updatePassword(String password) => _update(password: password);

  Future<void> _update(
      {String? email, String? password, String? redirectTo}) async {
    final context = capture();
    if (context == null ||
        !context.current() ||
        tokenSubject(context.accessToken) != context.account) {
      throw const AuthException(
          'Your session could not be verified. Sign in again.');
    }
    if (_busy) {
      throw const AuthException('An account update is already in progress.');
    }
    _busy = true;
    try {
      final body = <String, dynamic>{
        if (email != null) 'email': email,
        if (password != null) 'password': password
      };
      if (email != null) {
        final random = Random.secure();
        final verifier =
            base64UrlEncode(List<int>.generate(56, (_) => random.nextInt(256)))
                .replaceAll('=', '');
        await pkceStorage.setItem(key: verifierKey, value: verifier);
        if (!context.current()) {
          throw const AuthException(
              'Your account changed. Reopen your profile.');
        }
        body['code_challenge'] =
            base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
                .replaceAll('=', '');
        body['code_challenge_method'] = 's256';
      }
      if (!context.current()) {
        throw const AuthException('Your account changed. Reopen your profile.');
      }
      final endpoint = redirectTo == null
          ? context.endpoint
          : context.endpoint.replace(queryParameters: {
              ...context.endpoint.queryParameters,
              'redirect_to': redirectTo
            });
      final response = await client
          .put(endpoint,
              headers: {
                for (final entry in context.headers.entries)
                  if (entry.key.toLowerCase() != 'authorization')
                    entry.key: entry.value,
                'Authorization': 'Bearer ${context.accessToken}',
                'Content-Type': 'application/json'
              },
              body: jsonEncode(body))
          .timeout(timeout);
      if (!context.current()) {
        throw const AuthException(
            'Your account changed. Reopen the current account.');
      }
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = data?['code'] ?? data?['error_code'];
        if (code == 'weak_password') {
          throw AuthWeakPasswordException(
              message: 'Choose a stronger password.',
              statusCode: response.statusCode.toString(),
              reasons: const []);
        }
        throw AuthException(
            'Account update could not be verified. Please retry.',
            statusCode: response.statusCode.toString(),
            code: code is String ? code : null);
      }
      if (data == null ||
          UserResponse.fromJson(data).user?.id != context.account) {
        throw const AuthException(
            'Account update returned an unexpected acknowledgment.');
      }
      // The shared SDK keeps its current session/user. A verified email link
      // updates Auth normally through the SDK's own PKCE exchange later.
    } finally {
      _busy = false;
    }
  }
}

class _LazyPkceStorage extends GotrueAsyncStorage {
  GotrueAsyncStorage get storage => SupabaseConfig.authPkceStorage;
  @override
  Future<String?> getItem({required String key}) => storage.getItem(key: key);
  @override
  Future<void> setItem({required String key, required String value}) =>
      storage.setItem(key: key, value: value);
  @override
  Future<void> removeItem({required String key}) =>
      storage.removeItem(key: key);
}
