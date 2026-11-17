import 'package:tabby/core/services/serialized_pkce_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/core/services/auth_user_mutation.dart';

const actorA = '00000000-0000-4000-8000-000000000001',
    actorB = '00000000-0000-4000-8000-000000000002';
String token(String actor, [int generation = 0]) =>
    'synthetic.${base64UrlEncode(utf8.encode(jsonEncode({
          'sub': actor,
          'session_id':
              '00000000-0000-4000-8000-${generation.toString().padLeft(12, '0')}',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        }))).replaceAll('=', '')}.signature';
Map<String, dynamic> user(String actor,
        {String email = 'old@example.invalid'}) =>
    {
      'id': actor,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-11-01T00:00:00Z',
      'email': email
    };
String session(String actor, [int generation = 0]) => jsonEncode({
      'access_token': token(actor, generation),
      'refresh_token': 'synthetic-refresh-$actor-$generation',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'user': user(actor)
    });

class MemoryPkce extends GotrueAsyncStorage {
  final values = <String, String>{};
  bool fail = false;
  Completer<void>? blocked, started;
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    if (started != null && !started!.isCompleted) started!.complete();
    if (blocked != null) await blocked!.future;
    if (fail) throw StateError('Synthetic verifier persistence failure');
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<GoTrueClient> sdk(GotrueAsyncStorage storage,
      {http.Client? client}) async {
    final auth = GoTrueClient(
        url: 'https://auth.example.invalid/auth/v1',
        autoRefreshToken: false,
        asyncStorage: storage,
        httpClient: client ??
            MockClient((_) async => throw StateError('Unexpected SDK HTTP')));
    await auth.setInitialSession(session(actorA));
    addTearDown(auth.dispose);
    return auth;
  }

  AuthUserMutation transport(
          GoTrueClient auth, GotrueAsyncStorage storage, http.Client client,
          {bool Function()? current,
          Duration timeout = const Duration(seconds: 20)}) =>
      AuthUserMutation(
          capture: () {
            final captured = auth.currentSession!;
            return AuthMutationContext(
                account: captured.user.id,
                accessToken: captured.accessToken,
                endpoint:
                    Uri.parse('https://auth.example.invalid/auth/v1/user'),
                headers: const {
                  'apikey': 'synthetic-public-key',
                  'authorization': 'Bearer wrong-synthetic-header'
                },
                current: current ??
                    () =>
                        auth.currentSession?.accessToken ==
                        captured.accessToken);
          },
          pkceStorage: storage,
          client: client,
          timeout: timeout);

  test(
      'late A password acknowledgment never replaces real SDK B session/user or emits userUpdated',
      () async {
    final storage = MemoryPkce(), auth = await sdk(MemoryPkce());
    final events = <AuthChangeEvent>[];
    final subscription =
        auth.onAuthStateChange.listen((event) => events.add(event.event));
    addTearDown(subscription.cancel);
    final expectedToken = auth.currentSession!.accessToken;
    final started = Completer<void>(), response = Completer<http.Response>();
    final client = MockClient((request) {
      expect(request.headers['authorization'], 'Bearer $expectedToken');
      expect(jsonDecode(request.body), {'password': 'synthetic-only-password'});
      started.complete();
      return response.future;
    });
    addTearDown(client.close);
    final mutation = transport(auth, storage, client);
    final pending = mutation.updatePassword('synthetic-only-password');
    await started.future;
    await auth.setInitialSession(session(actorB));
    final activeToken = auth.currentSession!.accessToken;
    response.complete(http.Response(jsonEncode(user(actorA)), 200));
    await expectLater(pending, throwsA(isA<AuthException>()));
    expect(auth.currentUser!.id, actorB);
    expect(auth.currentSession!.accessToken, activeToken);
    expect(
        events.where((event) => event == AuthChangeEvent.userUpdated), isEmpty);
    expect(storage.values, isEmpty);
  });
  test('same-account relogin also discards the old response', () async {
    final storage = MemoryPkce(), auth = await sdk(MemoryPkce());
    final response = Completer<http.Response>(), started = Completer<void>();
    final client = MockClient((_) {
      started.complete();
      return response.future;
    });
    addTearDown(client.close);
    final pending = transport(auth, storage, client)
        .updatePassword('synthetic-only-password');
    await started.future;
    await auth.setInitialSession(session(actorA, 1));
    final current = auth.currentSession!.accessToken;
    response.complete(http.Response(
        jsonEncode(user(actorA, email: 'stale@example.invalid')), 200));
    await expectLater(pending, throwsA(isA<AuthException>()));
    expect(auth.currentSession!.accessToken, current);
    expect(auth.currentUser!.email, 'old@example.invalid');
  });
  test(
      'email request uses compatible PKCE and changes SDK email only after actual SDK exchange',
      () async {
    final backing = MemoryPkce();
    final storage = SerializedPkceStorage(
        delegate: backing, captureCurrent: () => () => true);
    String? challenge;
    final sdkClient = MockClient((request) async {
      expect(request.url.path, '/auth/v1/token');
      expect(request.url.queryParameters['grant_type'], 'pkce');
      final verifier = jsonDecode(request.body)['code_verifier'] as String;
      expect(
          base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
              .replaceAll('=', ''),
          challenge);
      final verified = jsonDecode(session(actorA)) as Map<String, dynamic>;
      verified['user'] = user(actorA, email: 'verified@example.invalid');
      return http.Response(jsonEncode(verified), 200);
    });
    addTearDown(sdkClient.close);
    final auth = await sdk(storage, client: sdkClient);
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      challenge = body['code_challenge'] as String;
      expect(body['code_challenge_method'], 's256');
      expect(body['email'], 'verified@example.invalid');
      expect(request.url.queryParameters['redirect_to'],
          'io.supabase.tabby://login-callback');
      return http.Response(jsonEncode(user(actorA)), 200);
    });
    addTearDown(client.close);
    await transport(auth, storage, client).updateEmail(
        'verified@example.invalid',
        redirectTo: 'io.supabase.tabby://login-callback');
    expect(auth.currentUser!.email, 'old@example.invalid');
    expect(backing.values.keys, [AuthUserMutation.verifierKey]);
    await auth.exchangeCodeForSession('synthetic-authorization-code');
    expect(auth.currentUser!.email, 'verified@example.invalid');
    expect(backing.values, isEmpty);
  });
  test('account change during PKCE persistence prevents the HTTP mutation',
      () async {
    final storage = MemoryPkce()
      ..blocked = Completer<void>()
      ..started = Completer<void>();
    final auth = await sdk(MemoryPkce());
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(jsonEncode(user(actorA)), 200);
    });
    addTearDown(client.close);
    final pending = transport(auth, storage, client)
        .updateEmail('new@example.invalid', redirectTo: 'fixture://callback');
    await storage.started!.future;
    await auth.setInitialSession(session(actorB));
    storage.blocked!.complete();
    await expectLater(pending, throwsA(isA<AuthException>()));
    expect(calls, 0);
    expect(auth.currentUser!.id, actorB);
  });
  test('inconsistent SDK user/JWT subject is rejected before transport',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    final mutation = AuthUserMutation(
        capture: () => AuthMutationContext(
            account: actorA,
            accessToken: token(actorB),
            endpoint: Uri.parse('https://auth.example.invalid/auth/v1/user'),
            headers: const {},
            current: () => true),
        pkceStorage: MemoryPkce(),
        client: client);
    await expectLater(mutation.updatePassword('synthetic-only-password'),
        throwsA(isA<AuthException>()));
    expect(calls, 0);
  });
  test('foreign actor success body is not an acknowledgment', () async {
    final auth = await sdk(MemoryPkce());
    final client =
        MockClient((_) async => http.Response(jsonEncode(user(actorB)), 200));
    addTearDown(client.close);
    await expectLater(
        transport(auth, MemoryPkce(), client)
            .updatePassword('synthetic-only-password'),
        throwsA(isA<AuthException>()));
    expect(auth.currentUser!.id, actorA);
  });
  for (final body in ['{}', '[]', 'invalid response']) {
    test('malformed success $body never mutates the SDK', () async {
      final auth = await sdk(MemoryPkce());
      final client = MockClient((_) async => http.Response(body, 200));
      addTearDown(client.close);
      await expectLater(
          transport(auth, MemoryPkce(), client)
              .updatePassword('synthetic-only-password'),
          throwsA(isA<AuthException>()));
      expect(auth.currentUser!.id, actorA);
    });
  }
  test('weak/same password errors preserve the existing service error contract',
      () async {
    final auth = await sdk(MemoryPkce());
    var weak = true;
    final client = MockClient((_) async => http.Response(
        jsonEncode({'code': weak ? 'weak_password' : 'same_password'}), 422));
    addTearDown(client.close);
    final mutation = transport(auth, MemoryPkce(), client);
    await expectLater(mutation.updatePassword('synthetic-only-password'),
        throwsA(isA<AuthWeakPasswordException>()));
    weak = false;
    await expectLater(
        mutation.updatePassword('synthetic-only-password'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', 'same_password')));
  });
  test(
      'concurrent account mutations submit once and release the guard after completion',
      () async {
    final auth = await sdk(MemoryPkce());
    final response = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((_) {
      calls++;
      return calls == 1
          ? response.future
          : Future.value(http.Response(jsonEncode(user(actorA)), 200));
    });
    addTearDown(client.close);
    final mutation = transport(auth, MemoryPkce(), client);
    final first = mutation.updatePassword('synthetic-only-password');
    await expectLater(mutation.updatePassword('another-synthetic-password'),
        throwsA(isA<AuthException>()));
    response.complete(http.Response(jsonEncode(user(actorA)), 200));
    await first;
    await mutation.updatePassword('another-synthetic-password');
    expect(calls, 2);
  });
  test(
      'timeout and late acknowledgment cannot install a user or keep the mutation guard locked',
      () async {
    final auth = await sdk(MemoryPkce());
    final response = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((_) {
      calls++;
      return calls == 1
          ? response.future
          : Future.value(http.Response(jsonEncode(user(actorA)), 200));
    });
    addTearDown(client.close);
    final mutation = transport(auth, MemoryPkce(), client,
        timeout: const Duration(milliseconds: 30));
    await expectLater(mutation.updatePassword('synthetic-only-password'),
        throwsA(isA<TimeoutException>()));
    await auth.setInitialSession(session(actorB));
    response.complete(http.Response(jsonEncode(user(actorA)), 200));
    await Future<void>.delayed(Duration.zero);
    expect(auth.currentUser!.id, actorB);
    await auth.setInitialSession(session(actorA));
    await mutation.updatePassword('synthetic-only-password');
    expect(calls, 2);
  });
  test(
      'failed PKCE persistence never sends email and retry uses a fresh verifier',
      () async {
    final storage = MemoryPkce()..fail = true;
    final auth = await sdk(MemoryPkce());
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(jsonEncode(user(actorA)), 200);
    });
    addTearDown(client.close);
    final mutation = transport(auth, storage, client);
    await expectLater(
        mutation.updateEmail('new@example.invalid',
            redirectTo: 'fixture://callback'),
        throwsStateError);
    expect(calls, 0);
    storage.fail = false;
    await mutation.updateEmail('new@example.invalid',
        redirectTo: 'fixture://callback');
    expect(calls, 1);
    expect(storage.values.values.single,
        isNot(contains('synthetic-only-password')));
    expect(storage.values.values.single, isNot(contains(token(actorA))));
  });
  test(
      'serialized PKCE writes keep the latest account flow after a slow old write',
      () async {
    var generation = 0;
    final backing = MemoryPkce()
      ..blocked = Completer<void>()
      ..started = Completer<void>();
    final storage = SerializedPkceStorage(
        delegate: backing,
        captureCurrent: () {
          final captured = generation;
          return () => captured == generation;
        });
    final old = storage.setItem(
        key: AuthUserMutation.verifierKey, value: 'old-synthetic-verifier');
    await backing.started!.future;
    generation++;
    final newer = storage.setItem(
        key: AuthUserMutation.verifierKey, value: 'new-synthetic-verifier');
    backing.blocked!.complete();
    await Future.wait([old, newer]);
    expect(await storage.getItem(key: AuthUserMutation.verifierKey),
        'new-synthetic-verifier');
  });
  test(
      'obsolete queued PKCE writer is rejected and does not prevent a newer writer',
      () async {
    var generation = 0;
    final backing = MemoryPkce()
      ..blocked = Completer<void>()
      ..started = Completer<void>();
    final storage = SerializedPkceStorage(
        delegate: backing,
        captureCurrent: () {
          final captured = generation;
          return () => captured == generation;
        });
    final first = storage.setItem(
        key: AuthUserMutation.verifierKey, value: 'first-synthetic-verifier');
    await backing.started!.future;
    final old = storage.setItem(
        key: AuthUserMutation.verifierKey,
        value: 'obsolete-synthetic-verifier');
    final rejected = expectLater(old, throwsA(isA<AuthException>()));
    generation++;
    final newer = storage.setItem(
        key: AuthUserMutation.verifierKey, value: 'latest-synthetic-verifier');
    backing.blocked!.complete();
    await Future.wait([first, rejected, newer]);
    expect(await storage.getItem(key: AuthUserMutation.verifierKey),
        'latest-synthetic-verifier');
    await storage.removeItem(key: AuthUserMutation.verifierKey);
    expect(await storage.getItem(key: AuthUserMutation.verifierKey), isNull);
  });
}
