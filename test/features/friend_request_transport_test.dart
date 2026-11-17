import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';

const actor = '11111111-1111-4111-8111-111111111111';
const otherActor = '22222222-2222-4222-8222-222222222222';
const friend = '33333333-3333-4333-8333-333333333333';
const requestId = '44444444-4444-4444-8444-444444444444';
const tabId = '55555555-5555-4555-8555-555555555555';
const code = 'TAB-7K4P2M';
Map<String, Object?> requestRow() => {
  'id': requestId,
  'requester_id': actor,
  'addressee_id': friend,
  'status': 'pending',
  'created_at': '2026-11-13T00:00:00Z',
  'responded_at': null,
  'requester_display_name': 'Synthetic sender',
  'addressee_display_name': 'Synthetic friend',
};
String syntheticSession(String id) {
  String part(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final jwt =
      '${part({'alg': 'HS256'})}.${part({'sub': id, 'role': 'authenticated', 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})}.synthetic';
  return jsonEncode({
    'access_token': jwt,
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 86400,
    'user': {
      'id': id,
      'aud': 'authenticated',
      'role': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = SupabaseTabbyRepository.instance;
  late _Server fake;
  HttpOverrides? previous;
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    fake = await _Server.start();
    previous = HttpOverrides.current;
    HttpOverrides.global = _Loopback(fake.http.port);
    await SupabaseConfig.initialize(
      url: 'http://127.0.0.1:${fake.http.port}',
      anonKey: 'synthetic-anon',
      debug: false,
    );
    String part(Object value) =>
        base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final jwt =
        '${part({'alg': 'HS256'})}.${part({'sub': actor, 'role': 'authenticated', 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})}.synthetic';
    await SupabaseConfig.auth.recoverSession(
      jsonEncode({
        'access_token': jwt,
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 86400,
        'user': {
          'id': actor,
          'aud': 'authenticated',
          'role': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    await fake.http.close(force: true);
    HttpOverrides.global = previous;
  });
  setUp(() {
    fake.reset();
    SupabaseConfig.debugUserIdOverride = actor;
    SupabaseConfig.captureSession();
  });
  tearDown(() async {
    SupabaseConfig.debugUserIdOverride = null;
    await SupabaseConfig.client.removeAllChannels();
  });

  void invalidate(bool sameAccount) {
    SupabaseConfig.debugUserIdOverride = otherActor;
    SupabaseConfig.captureSession();
    if (sameAccount) {
      SupabaseConfig.debugUserIdOverride = actor;
      SupabaseConfig.captureSession();
    }
  }

  for (final same in [false, true]) {
    for (final operation in [
      'find_user_by_friend_code',
      'send_friend_request',
      'list_friend_requests',
      'respond_friend_request',
    ]) {
      test(
        '$operation discards ${same ? 'same-account relogin' : 'other-account'} response',
        () async {
          fake.blocked = operation;
          final Future<dynamic> result = switch (operation) {
            'find_user_by_friend_code' => repository.findUserByFriendCode(code),
            'send_friend_request' => repository.sendFriendRequest(
              friendCode: code,
            ),
            'list_friend_requests' => repository.fetchFriendRequests(actor),
            _ => repository.respondToFriendRequest(
              friendshipId: requestId,
              accept: true,
            ),
          };
          await fake.entered.future;
          invalidate(same);
          fake.release.complete();
          expect(
            await result,
            operation == 'list_friend_requests' ? isEmpty : isNull,
          );
        },
      );
    }
  }
  test(
    'late send cannot add account A request to account B notifier',
    () async {
      final notifier = TabbyNotifier(loadInitialData: false);
      addTearDown(notifier.dispose);
      fake.blocked = 'send_friend_request';
      final result = notifier.sendFriendRequestByCode(code);
      await fake.entered.future;
      invalidate(false);
      fake.release.complete();
      expect(await result, isNull);
      expect(notifier.state.friendRequests, isEmpty);
    },
  );
  test(
    'accepted and declined acknowledgments keep the actual SQL contract',
    () async {
      expect(
        await repository.respondToFriendRequest(
          friendshipId: requestId,
          accept: true,
        ),
        tabId,
      );
      expect(
        await repository.respondToFriendRequest(
          friendshipId: requestId,
          accept: false,
        ),
        '',
      );
    },
  );
  test(
    'current-session lookup, send and list retain the actual request identity',
    () async {
      expect((await repository.findUserByFriendCode(code))?.id, friend);
      final sent = await repository.sendFriendRequest(friendCode: code);
      expect(sent?.id, requestId);
      expect(sent?.requesterId, actor);
      expect(sent?.currentUserId, actor);
      expect(
        (await repository.fetchFriendRequests(actor)).single.id,
        requestId,
      );
    },
  );
  for (final operation in ['send_friend_request', 'respond_friend_request']) {
    test(
      '$operation never dispatches an A intent using a newly installed B token',
      () async {
        final switched = Completer<void>();
        scheduleMicrotask(() async {
          await SupabaseConfig.auth.recoverSession(
            syntheticSession(otherActor),
          );
          switched.complete();
        });
        final result = operation == 'send_friend_request'
            ? repository.sendFriendRequest(friendCode: code)
            : repository.respondToFriendRequest(
                friendshipId: requestId,
                accept: true,
              );
        try {
          await switched.future;
          await result;
          expect(fake.actors[operation], actor);
        } finally {
          await SupabaseConfig.auth.recoverSession(syntheticSession(actor));
          await Future<void>.delayed(Duration.zero);
        }
      },
    );
  }
  for (final bad in [
    {'request_id': otherActor, 'status': 'accepted', 'tab_id': tabId},
    {'request_id': requestId, 'status': 'declined', 'tab_id': tabId},
    {'request_id': requestId, 'status': 'accepted', 'tab_id': ''},
    {'tab_id': tabId},
  ]) {
    test(
      'wrong or incomplete decision acknowledgment is not success: $bad',
      () async {
        fake.decisionReply = bad;
        expect(
          await repository.respondToFriendRequest(
            friendshipId: requestId,
            accept: true,
          ),
          isNull,
        );
      },
    );
  }
}

class _Loopback extends HttpOverrides {
  _Loopback(this.port);
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      if (uri.host != '127.0.0.1' || uri.port != port) {
        throw StateError(
          'External network forbidden in friend transport fixture',
        );
      }
      return 'DIRECT';
    };
    return client;
  }
}

class _Server {
  _Server(this.http);
  final HttpServer http;
  String? blocked;
  Map<String, String>? decisionReply;
  final actors = <String, String?>{};
  Completer<void> entered = Completer<void>(), release = Completer<void>();
  void reset() {
    actors.clear();
    blocked = null;
    decisionReply = null;
    entered = Completer<void>();
    release = Completer<void>();
  }

  static Future<_Server> start() async {
    final fake = _Server(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake.http.listen(fake.handle);
    return fake;
  }

  Future<void> handle(HttpRequest request) async {
    final operation = request.uri.path.split('/').last;
    final bearer = request.headers.value('authorization') ?? '';
    try {
      actors[operation] =
          (jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(bearer.split('.')[1])),
                ),
              ) as Map)['sub']
              as String?;
    } catch (_) {}
    final raw = await utf8.decoder.bind(request).join();
    final decoded = raw.isEmpty ? null : jsonDecode(raw);
    final params = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (operation == blocked) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    final Object body = switch (operation) {
      'find_user_by_friend_code' => [
        {'id': friend, 'display_name': 'Synthetic friend', 'friend_code': code},
      ],
      'send_friend_request' || 'list_friend_requests' => [requestRow()],
      'respond_friend_request' =>
        decisionReply ??
            {
              'request_id': requestId,
              'status': params['p_accept'] == true ? 'accepted' : 'declined',
              'tab_id': params['p_accept'] == true ? tabId : '',
            },
      _ => [],
    };
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}
