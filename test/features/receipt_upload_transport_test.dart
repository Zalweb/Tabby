import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/services/receipt_attachment_service.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _expenseId = '44444444-4444-4444-8444-444444444444';
const _anonKey = 'local-test-anon-key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeStorageServer fake;
  late String accessToken;
  HttpOverrides? previousHttpOverrides;
  var initialized = false;

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    fake = await _FakeStorageServer.start();
    previousHttpOverrides = HttpOverrides.current;
    // Replace Flutter's blanket HTTP-400 stub with real loopback-only sockets.
    HttpOverrides.global = _LoopbackHttpOverrides(fake.server.port);
    await SupabaseConfig.initialize(
      url: 'http://127.0.0.1:${fake.server.port}',
      anonKey: _anonKey,
      debug: false,
    );
    initialized = true;

    final expiry = DateTime.now().add(const Duration(days: 1));
    String jwtPart(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    accessToken =
        '${jwtPart({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${jwtPart({'sub': _userId, 'role': 'authenticated', 'aud': 'authenticated', 'exp': expiry.millisecondsSinceEpoch ~/ 1000})}.'
        '${base64Url.encode(utf8.encode('synthetic-signature')).replaceAll('=', '')}';
    await SupabaseConfig.auth.recoverSession(
      jsonEncode({
        'access_token': accessToken,
        'refresh_token': 'synthetic-refresh-token',
        'token_type': 'bearer',
        'expires_in': const Duration(days: 1).inSeconds,
        'user': {
          'id': _userId,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'transport@example.invalid',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    expect(SupabaseConfig.auth.currentSession?.isExpired, isFalse);
    expect(SupabaseConfig.currentUser?.id, _userId);
  });

  tearDownAll(() async {
    try {
      if (initialized) await Supabase.instance.dispose();
    } finally {
      await fake.close();
      HttpOverrides.global = previousHttpOverrides;
    }
  });

  setUp(() {
    fake.reset();
    FlutterSecureStorage.setMockInitialValues({});
    expect(SupabaseConfig.currentUser?.id, _userId);
  });

  tearDown(() async {
    await SupabaseConfig.client.removeAllChannels();
    expect(fake.errors, isEmpty, reason: 'Unexpected fake server requests');
    for (final request in fake.requests) {
      expect(request.headers['authorization'], 'Bearer $accessToken');
      expect(request.headers['apikey'], _anonKey);
    }
  });

  test('receipt snapshot uploads exact bytes after local file is deleted', () async {
    final directory = await Directory.systemTemp.createTemp('tabby-receipt-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/receipt.png');
    // A real PNG includes binary bytes that cannot safely round-trip via UTF-8.
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
    );
    await file.writeAsBytes(bytes, flush: true);
    final encoded = await ReceiptAttachmentService.readPendingReceiptBytes(
      file.path,
      userId: _userId,
    );
    expect(encoded, base64Encode(bytes));
    await file.delete();
    expect(await file.exists(), isFalse);

    final storagePath = await ReceiptAttachmentService.uploadPendingReceipt(
      file.path,
      entryKey: _expenseId,
      userId: _userId,
      encodedBytes: encoded,
    );
    expect(storagePath, '$_userId/$_expenseId.png');
    expect(fake.requests, hasLength(1));
    final request = fake.requests.single;
    expect(request.method, 'POST');
    expect(
      request.uri.path,
      '/storage/v1/object/payment-proofs/$_userId/$_expenseId.png',
    );
    expect(request.headers['x-upsert'], 'false');
    expect(request.headers['content-type'], startsWith('multipart/form-data;'));
    expect(request.uploadContentType, 'image/png');
    expect(request.uploadBytes, orderedEquals(bytes));
    expect(request.responseStatus, 200);
    expect(fake.storage.keys, ['payment-proofs/$_userId/$_expenseId.png']);
    expect(fake.storage.values.single, orderedEquals(bytes));
    expect(await file.exists(), isFalse);
  });

  const receiptPath = 'tabby-receipt:$_userId:synthetic.png';
  const objectKey = 'payment-proofs/$_userId/$_expenseId.png';
  Future<String?> replay(List<int> bytes) =>
      ReceiptAttachmentService.uploadPendingReceipt(
        receiptPath,
        entryKey: _expenseId,
        userId: _userId,
        encodedBytes: base64Encode(bytes),
      );

  test(
    'replay after financial commit reuses identical immutable proof bytes',
    () async {
      await replay([1, 128, 255]);
      // The RPC committed but its response was lost. The queue still has its
      // original owned-byte reference; RLS now forbids updating this object.
      fake.referenced.add(objectKey);
      expect(await replay([1, 128, 255]), '$_userId/$_expenseId.png');
      expect(fake.storage[objectKey], [1, 128, 255]);
      expect(fake.requests.map((request) => request.method), [
        'POST',
        'POST',
        'GET',
      ]);
    },
  );

  test(
    'same upload identity with different bytes never overwrites an object',
    () async {
      await replay([1, 2, 3]);
      await expectLater(replay([4, 5, 6]), throwsStateError);
      expect(fake.storage[objectKey], [1, 2, 3]);
    },
  );

  test(
    'ambiguous upload response is reconciled on retry without an overwrite',
    () async {
      fake.loseNextUploadResponse = true;
      await expectLater(replay([1, 2, 3]), throwsA(isA<StorageException>()));
      expect(fake.storage[objectKey], [1, 2, 3]);
      expect(await replay([1, 2, 3]), '$_userId/$_expenseId.png');
      expect(fake.requests.map((request) => request.method), [
        'POST',
        'POST',
        'GET',
      ]);
    },
  );

  test(
    'duplicate without authorized byte read is never acknowledged',
    () async {
      fake.storage[objectKey] = Uint8List.fromList([1, 2, 3]);
      fake.denyDownload = true;
      await expectLater(replay([1, 2, 3]), throwsA(isA<StorageException>()));
      expect(fake.storage[objectKey], [1, 2, 3]);
    },
  );

  test(
    'ordinary upload denial never falls back to trusting an existing path',
    () async {
      fake.denyUpload = true;
      await expectLater(replay([1, 2, 3]), throwsA(isA<StorageException>()));
      expect(fake.storage, isEmpty);
      expect(fake.requests.map((request) => request.method), ['POST']);
    },
  );

  test(
    'account change during duplicate read discards upload acknowledgment',
    () async {
      fake.storage[objectKey] = Uint8List.fromList([1, 2, 3]);
      fake.beforeDownloadReply = () {
        SupabaseConfig.debugUserIdOverride = 'another-account';
      };
      try {
        await expectLater(replay([1, 2, 3]), throwsStateError);
        expect(fake.storage[objectKey], [1, 2, 3]);
      } finally {
        SupabaseConfig.debugUserIdOverride = null;
      }
    },
  );

  test('invalid retained byte sizes never reach Storage', () async {
    for (final bytes in [<int>[], Uint8List(5 * 1024 * 1024 + 1)]) {
      await expectLater(replay(bytes), throwsFormatException);
    }
    expect(fake.requests, isEmpty);
  });
}

class _LoopbackHttpOverrides extends HttpOverrides {
  _LoopbackHttpOverrides(this.port);
  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      if (uri.scheme != 'http' || uri.host != '127.0.0.1' || uri.port != port) {
        throw StateError('External network forbidden in transport tests: $uri');
      }
      return 'DIRECT';
    };
    return client;
  }
}

class _RecordedRequest {
  _RecordedRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List body;
  int? responseStatus;
  Object? responseJson;
  Uint8List? uploadBytes;
  String? uploadContentType;
}

/// Minimal Supabase Storage behavior for receipt uploads.
class _FakeStorageServer {
  _FakeStorageServer(this.server);
  final HttpServer server;
  late final StreamSubscription<HttpRequest> _subscription;
  final requests = <_RecordedRequest>[];
  final errors = <String>[];
  final storage = <String, Uint8List>{};
  final referenced = <String>{};
  bool loseNextUploadResponse = false, denyDownload = false, denyUpload = false;
  void Function()? beforeDownloadReply;

  static Future<_FakeStorageServer> start() async {
    final fake = _FakeStorageServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake._subscription = fake.server.listen(fake._handle);
    return fake;
  }

  void reset() {
    requests.clear();
    errors.clear();
    storage.clear();
    referenced.clear();
    loseNextUploadResponse = denyDownload = denyUpload = false;
    beforeDownloadReply = null;
  }

  Future<void> close() async {
    await server.close(force: true);
    await _subscription.cancel();
  }

  Future<void> _handle(HttpRequest request) async {
    _RecordedRequest? recorded;
    try {
      final body = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(',');
      });
      recorded = _RecordedRequest(
        request.method,
        request.uri,
        headers,
        Uint8List.fromList(body),
      );
      requests.add(recorded);
      final path = request.uri.path;
      if (path.startsWith('/storage/v1/object/') && request.method == 'POST') {
        final boundary = request.headers.contentType?.parameters['boundary'];
        if (boundary == null) throw StateError('Missing multipart boundary');
        final parts = await MimeMultipartTransformer(boundary)
            .bind(Stream<List<int>>.value(body))
            .toList();
        final filePart = parts.singleWhere(
          (part) =>
              part.headers['content-disposition']?.contains('filename=') ??
              false,
        );
        final fileBytes = await filePart.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        recorded.uploadContentType = filePart.headers['content-type'];
        recorded.uploadBytes = Uint8List.fromList(fileBytes);
        final key = path.substring('/storage/v1/object/'.length);
        if (denyUpload ||
            (headers['x-upsert'] == 'true' && referenced.contains(key))) {
          await _reply(request, recorded, 403, {
            'statusCode': '403',
            'error': 'Unauthorized',
            'message': 'new row violates row-level security policy',
          });
          return;
        }
        if (storage.containsKey(key) && headers['x-upsert'] != 'true') {
          // Storage has returned both HTTP 400 and 409 for Duplicate; the
          // structured statusCode remains 409 in the compatible response.
          await _reply(request, recorded, 400, {
            'statusCode': '409',
            'error': 'Duplicate',
            'message': 'The resource already exists',
          });
          return;
        }
        storage[key] = recorded.uploadBytes!;
        if (loseNextUploadResponse) {
          loseNextUploadResponse = false;
          await _reply(request, recorded, 503, {
            'statusCode': '503',
            'error': 'Unavailable',
            'message': 'Synthetic lost upload acknowledgment',
          });
          return;
        }
        await _reply(request, recorded, 200, {'Key': key});
        return;
      }
      if (path.startsWith('/storage/v1/object/') && request.method == 'GET') {
        final key = path.substring('/storage/v1/object/'.length);
        if (denyDownload || !storage.containsKey(key)) {
          await _reply(request, recorded, 403, {
            'statusCode': '403',
            'error': 'Unauthorized',
            'message': 'Object is not readable',
          });
          return;
        }
        beforeDownloadReply?.call();
        recorded.responseStatus = 200;
        request.response.headers.contentType = ContentType.binary;
        request.response.add(storage[key]!);
        await request.response.close();
        return;
      }
      throw StateError('Unhandled path: $path');
    } catch (error) {
      errors.add(error.toString());
      await _reply(request, recorded, 400, {
        'code': 'FAKE_PROTOCOL_ERROR',
        'message': error.toString(),
      });
    }
  }

  Future<void> _reply(
    HttpRequest httpRequest,
    _RecordedRequest? request,
    int status,
    Object json,
  ) async {
    request?.responseStatus = status;
    request?.responseJson = json;
    httpRequest.response.statusCode = status;
    httpRequest.response.headers.contentType = ContentType.json;
    httpRequest.response.write(jsonEncode(json));
    await httpRequest.response.close();
  }
}
