import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/services/receipt_attachment_service.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:uuid/uuid.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _otherUserId = '22222222-2222-4222-8222-222222222222';
const _tabId = '33333333-3333-4333-8333-333333333333';
const _expenseId = '44444444-4444-4444-8444-444444444444';
const _paymentId = '55555555-5555-4555-8555-555555555555';
const _anonKey = 'local-test-anon-key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repository = SupabaseTabbyRepository.instance;
  late _FakeSupabase fake;
  late String accessToken;
  HttpOverrides? previousHttpOverrides;
  var initialized = false;
  _FakeSupabase? serverToClose;
  final notificationCalls = <MethodCall>[];
  final scheduledReminderIds = <int>{};
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity_status');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    // Keep the constructor's connectivity listener, but never emit online events.
    messenger.setMockMethodCallHandler(connectivityChannel, (call) async {
      if (call.method != 'listen' && call.method != 'cancel') {
        throw StateError('Unexpected connectivity call: ${call.method}');
      }
      return null;
    });
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      notificationCalls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'zonedSchedule':
          scheduledReminderIds.add((call.arguments as Map)['id'] as int);
          return null;
        case 'cancel':
          scheduledReminderIds.remove((call.arguments as Map)['id'] as int);
          return null;
        default:
          throw StateError('Unexpected notification call: ${call.method}');
      }
    });
    await TabbyNotificationService.instance.initialize();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    fake = await _FakeSupabase.start();
    serverToClose = fake;
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
    accessToken = '${jwtPart({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${jwtPart({
          'sub': _userId,
          'role': 'authenticated',
          'aud': 'authenticated',
          'exp': expiry.millisecondsSinceEpoch ~/ 1000
        })}.'
        '${base64Url.encode(utf8.encode('synthetic-signature')).replaceAll('=', '')}';
    await SupabaseConfig.auth.recoverSession(jsonEncode({
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
    }));
    expect(SupabaseConfig.auth.currentSession?.isExpired, isFalse);
    expect(SupabaseConfig.currentUser?.id, _userId);
    expect(SupabaseConfig.debugUserIdOverride, isNull);
  });

  tearDownAll(() async {
    try {
      if (initialized) await Supabase.instance.dispose();
    } finally {
      await serverToClose?.close();
      HttpOverrides.global = previousHttpOverrides;
      messenger.setMockMethodCallHandler(notificationsChannel, null);
      messenger.setMockMethodCallHandler(connectivityChannel, null);
    }
  });

  setUp(() {
    fake.reset();
    FlutterSecureStorage.setMockInitialValues({});
    notificationCalls.clear();
    scheduledReminderIds.clear();
    // Snapshot the authenticated actor without subscribing to auth events.
    expect(SupabaseConfig.currentUser?.id, _userId);
    expect(SupabaseConfig.debugUserIdOverride, isNull);
  });

  tearDown(() async {
    await SupabaseConfig.client.removeAllChannels();
    expect(fake.errors, isEmpty, reason: 'Unexpected fake server requests');
    for (final request in fake.requests) {
      expect(request.headers['authorization'], 'Bearer $accessToken');
      expect(request.headers['apikey'], _anonKey);
    }
  });

  Future<void> logExpense() => repository.logExpense(
        transactionId: _expenseId,
        tabId: _tabId,
        title: 'Transport regression lunch',
        totalAmountCentavos: 10001,
        category: ExpenseCategory.food,
        paidByUserId: _userId,
        myShareCentavos: 5000,
        counterpartShareCentavos: 5001,
        currentUserId: _userId,
        counterpartId: _otherUserId,
        dueDate: DateTime.utc(2026, 11, 1),
      );

  Future<void> submitPayment() => repository.recordPayment(
        paymentId: _paymentId,
        tabId: _tabId,
        amountCentavos: 5001,
        method: PaymentMethod.gcash,
        paidByUserId: _userId,
        receivedByUserId: _otherUserId,
        note: 'Transport regression settlement',
      );

  test('expense retry repairs partial write without duplicate financial rows',
      () async {
    fake.failNextParticipantPost = true;
    await expectLater(logExpense(), throwsA(_transientFailure));
    expect(fake.transactions.keys, [_expenseId]);
    expect(fake.participants, isEmpty);
    expect(
        fake.requests.map((request) => '${request.method} ${request.uri.path}'),
        [
          'GET /rest/v1/tab_members',
          'POST /rest/v1/transactions',
          'POST /rest/v1/transaction_participants',
        ]);

    await logExpense();
    expect(fake.transactions, hasLength(1));
    expect(fake.participants, hasLength(2));
    final persistedTransaction = Map<String, dynamic>.from(
      fake.transactions[_expenseId]!,
    );
    final persistedParticipants = [
      for (final row in fake.participants.values)
        Map<String, dynamic>.from(row),
    ];
    // A successful replay also exercises verification of ignored participant IDs.
    await logExpense();
    expect(fake.transactions.values, [persistedTransaction]);
    expect(fake.participants.values, persistedParticipants);

    final expectedTransaction = {
      'id': _expenseId,
      'tab_id': _tabId,
      'created_by': _userId,
      'transaction_type': 'shared_expense',
      'category': 'food',
      'description': 'Transport regression lunch',
      'total_amount_centavos': 10001,
      'currency': 'PHP',
      'status': 'acknowledged',
      'due_date': '2026-11-01',
    };
    final expectedParticipants = [
      {
        'id': const Uuid().v5(_expenseId, 'user_id:$_userId'),
        'transaction_id': _expenseId,
        'user_id': _userId,
        'participant_role': 'payer',
        'share_amount_centavos': 5000,
        'acknowledged': true,
      },
      {
        'id': const Uuid().v5(_expenseId, 'user_id:$_otherUserId'),
        'transaction_id': _expenseId,
        'user_id': _otherUserId,
        'participant_role': 'debtor',
        'share_amount_centavos': 5001,
        'acknowledged': false,
      },
    ];
    final transactionPosts = fake.forTable('transactions', 'POST');
    final participantPosts = fake.forTable('transaction_participants', 'POST');
    expect(transactionPosts, hasLength(3));
    expect(participantPosts, hasLength(3));
    for (final post in transactionPosts) {
      _expectInsertOnly(post);
      expect(post.jsonRows, [expectedTransaction]);
    }
    for (final post in participantPosts) {
      _expectInsertOnly(post);
      expect(post.jsonRows, expectedParticipants);
    }
    expect(transactionPosts.map((request) => request.responseStatus),
        [201, 201, 201]);
    expect(transactionPosts.map((request) => request.responseJson), [
      [
        {'id': _expenseId}
      ],
      [],
      [],
    ]);
    expect(participantPosts.map((request) => request.responseStatus),
        [503, 201, 201]);
    expect(participantPosts.last.responseJson, isEmpty);
    final transactionGets = fake.forTable('transactions', 'GET');
    expect(transactionGets, hasLength(2));
    for (final get in transactionGets) {
      _expectVerification(get, 'tab_id', _tabId, {_expenseId});
    }
    final participantGets = fake.forTable('transaction_participants', 'GET');
    expect(participantGets, hasLength(1));
    _expectVerification(participantGets.single, 'transaction_id', _expenseId,
        expectedParticipants.map((row) => row['id'] as String).toSet());
    final memberGets = fake.forTable('tab_members', 'GET');
    expect(memberGets, hasLength(3));
    for (final get in memberGets) {
      expect(get.uri.queryParameters,
          {'select': 'user_id,contact_id', 'tab_id': 'eq.$_tabId'});
    }
    expect(fake.transactions.values, [expectedTransaction]);
    expect(fake.participants.values, expectedParticipants);
  });

  test('payment failure, retry and successful replay persist one payment',
      () async {
    fake.failNextPaymentPost = true;
    await expectLater(submitPayment(), throwsA(_transientFailure));
    expect(fake.payments, isEmpty);
    expect(fake.forTable('payments', 'POST'), hasLength(1));

    await submitPayment();
    expect(fake.payments.keys, [_paymentId]);
    final persisted = Map<String, dynamic>.from(fake.payments[_paymentId]!);
    await submitPayment();
    expect(fake.payments.values, [persisted]);
    final expectedPayment = {
      'id': _paymentId,
      'tab_id': _tabId,
      'submitted_by': _userId,
      'amount_centavos': 5001,
      'payment_method': 'gcash',
      'note': 'Transport regression settlement',
      'status': 'submitted',
    };
    final posts = fake.forTable('payments', 'POST');
    expect(posts, hasLength(3));
    for (final post in posts) {
      _expectInsertOnly(post);
      expect(post.jsonRows, [expectedPayment]);
    }
    expect(posts.map((request) => request.responseStatus), [503, 201, 201]);
    expect(posts[1].responseJson, [
      {'id': _paymentId}
    ]);
    expect(posts.last.responseJson, isEmpty);
    final gets = fake.forTable('payments', 'GET');
    expect(gets, hasLength(1));
    _expectVerification(gets.single, 'tab_id', _tabId, {_paymentId});
    expect(fake.payments.values, [expectedPayment]);
  });

  test('debtor cannot claim confirmation through confirmedByUserId', () async {
    await repository.recordPayment(
      paymentId: _paymentId,
      tabId: _tabId,
      amountCentavos: 12345,
      method: PaymentMethod.maya,
      paidByUserId: _userId,
      receivedByUserId: _otherUserId,
      confirmedByUserId: _otherUserId,
    );
    final post = fake.forTable('payments', 'POST').single;
    _expectInsertOnly(post);
    final expected = {
      'id': _paymentId,
      'tab_id': _tabId,
      'submitted_by': _userId,
      'amount_centavos': 12345,
      'payment_method': 'maya',
      'status': 'submitted',
    };
    expect(post.jsonRows, [expected]);
    final row = post.jsonRows.single;
    // Omitted keys are distinct from JSON null for server defaults and triggers.
    expect(row.containsKey('confirmed_by'), isFalse);
    expect(row.containsKey('confirmed_at'), isFalse);
    expect(fake.payments.values, [expected]);
    expect(fake.forTable('payments', 'GET'), isEmpty);
  });

  test('creditor confirms another debtor using authenticated creditor identity',
      () async {
    final before = DateTime.now().toUtc();
    await repository.recordPayment(
      paymentId: _paymentId,
      tabId: _tabId,
      amountCentavos: 5001,
      method: PaymentMethod.cash,
      paidByUserId: _otherUserId,
      receivedByUserId: _userId,
      // A claimed different confirmer must not override the authenticated user.
      confirmedByUserId: _otherUserId,
    );
    final after = DateTime.now().toUtc();
    final post = fake.forTable('payments', 'POST').single;
    _expectInsertOnly(post);
    final row = post.jsonRows.single;
    expect(row, {
      'id': _paymentId,
      'tab_id': _tabId,
      'submitted_by': _otherUserId,
      'amount_centavos': 5001,
      'payment_method': 'cash',
      'status': 'confirmed',
      'confirmed_by': _userId,
      'confirmed_at': isA<String>(),
    });
    final confirmedAt = DateTime.parse(row['confirmed_at'] as String);
    expect(confirmedAt.isUtc, isTrue);
    expect(confirmedAt.isBefore(before), isFalse);
    expect(confirmedAt.isAfter(after), isFalse);
    expect(fake.payments.values, [row]);
    expect(fake.forTable('payments', 'GET'), isEmpty);
  });

  test('receipt snapshot uploads exact bytes after local file is deleted',
      () async {
    final directory = await Directory.systemTemp.createTemp('tabby-transport-');
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
    expect(request.uri.path,
        '/storage/v1/object/payment-proofs/$_userId/$_expenseId.png');
    expect(request.headers['x-upsert'], 'true');
    expect(request.headers['content-type'], startsWith('multipart/form-data;'));
    expect(request.uploadContentType, 'image/png');
    expect(request.uploadBytes, orderedEquals(bytes));
    expect(request.responseStatus, 200);
    expect(fake.storage.keys, ['payment-proofs/$_userId/$_expenseId.png']);
    expect(fake.storage.values.single, orderedEquals(bytes));
    expect(await file.exists(), isFalse);
  });
}

final _transientFailure = isA<PostgrestException>()
    .having((error) => error.code, 'code', 'TEST_TRANSIENT_503')
    .having((error) => error.message, 'message', 'Injected transient failure');

void _expectInsertOnly(_RecordedRequest request) {
  expect(request.method, 'POST');
  expect(request.uri.queryParameters['on_conflict'], 'id');
  expect(request.uri.queryParameters['select'], 'id');
  expect(request.headers['content-type'], startsWith('application/json'));
  final preferences = request.headers['prefer']!
      .split(',')
      .map((value) => value.trim())
      .toSet();
  expect(preferences, contains('resolution=ignore-duplicates'));
  expect(preferences, contains('return=representation'));
  expect(preferences, isNot(contains('resolution=merge-duplicates')));
}

void _expectVerification(_RecordedRequest request, String parentColumn,
    String parentId, Set<String> ids) {
  expect(request.uri.queryParameters['select'], 'id');
  expect(request.uri.queryParameters[parentColumn], 'eq.$parentId');
  expect(_filterIds(request.uri.queryParameters['id']!), ids);
  expect(request.responseJson, [
    for (final id in ids) {'id': id},
  ]);
}

Set<String> _filterIds(String filter) {
  if (!filter.startsWith('in.(') || !filter.endsWith(')')) {
    throw FormatException('Expected an ID in-filter, got $filter');
  }
  // PostgREST permits quoted string values; the SDK quotes UUIDs as well.
  return filter
      .substring(4, filter.length - 1)
      .split(',')
      .map((value) =>
          value.startsWith('"') ? jsonDecode(value) as String : value)
      .toSet();
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

  List<Map<String, dynamic>> get jsonRows =>
      List<Map<String, dynamic>>.from(jsonDecode(utf8.decode(body)) as List);
}

/// Minimal PostgREST/storage behavior, with state independent of repository code.
class _FakeSupabase {
  _FakeSupabase(this.server);
  final HttpServer server;
  late final StreamSubscription<HttpRequest> _subscription;
  final requests = <_RecordedRequest>[];
  final errors = <String>[];
  final transactions = <String, Map<String, dynamic>>{};
  final participants = <String, Map<String, dynamic>>{};
  final payments = <String, Map<String, dynamic>>{};
  final storage = <String, Uint8List>{};
  bool failNextParticipantPost = false;
  bool failNextPaymentPost = false;

  static Future<_FakeSupabase> start() async {
    final fake = _FakeSupabase(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fake._subscription = fake.server.listen(fake._handle);
    return fake;
  }

  void reset() {
    requests.clear();
    errors.clear();
    transactions.clear();
    participants.clear();
    payments.clear();
    storage.clear();
    failNextParticipantPost = false;
    failNextPaymentPost = false;
  }

  List<_RecordedRequest> forTable(String table, String method) => requests
      .where((request) =>
          request.method == method && request.uri.path == '/rest/v1/$table')
      .toList();

  Future<void> close() async {
    await server.close(force: true);
    await _subscription.cancel();
  }

  Future<void> _handle(HttpRequest httpRequest) async {
    _RecordedRequest? request;
    try {
      final body = await httpRequest
          .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      final headers = <String, String>{};
      httpRequest.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(',');
      });
      request = _RecordedRequest(httpRequest.method, httpRequest.uri, headers,
          Uint8List.fromList(body));
      requests.add(request);
      final path = request.uri.path;
      // Dashboard loads use a read-only RPC plus nested tab/notification reads.
      if ((path == '/rest/v1/rpc/list_friend_requests' &&
              request.method == 'POST') ||
          ((path == '/rest/v1/tabs' || path == '/rest/v1/notifications') &&
              request.method == 'GET')) {
        await _reply(httpRequest, request, 200, <Object>[]);
        return;
      }
      if (path.startsWith('/storage/v1/object/') && request.method == 'POST') {
        final boundary =
            httpRequest.headers.contentType?.parameters['boundary'];
        if (boundary == null) throw StateError('Missing multipart boundary');
        final parts = await MimeMultipartTransformer(boundary)
            .bind(Stream<List<int>>.value(body))
            .toList();
        final filePart = parts.singleWhere((part) =>
            part.headers['content-disposition']?.contains('filename=') ??
            false);
        final fileBytes = await filePart
            .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
        request.uploadContentType = filePart.headers['content-type'];
        request.uploadBytes = Uint8List.fromList(fileBytes);
        final key = path.substring('/storage/v1/object/'.length);
        storage[key] = request.uploadBytes!;
        await _reply(httpRequest, request, 200, {'Key': key});
        return;
      }
      if (path == '/rest/v1/tab_members' && request.method == 'GET') {
        final rows = request.uri.queryParameters['tab_id'] == 'eq.$_tabId'
            ? [
                {'user_id': _userId, 'contact_id': null},
                {'user_id': _otherUserId, 'contact_id': null},
              ]
            : <Map<String, dynamic>>[];
        await _reply(httpRequest, request, 200, rows);
        return;
      }
      final tables = {
        '/rest/v1/transactions': transactions,
        '/rest/v1/transaction_participants': participants,
        '/rest/v1/payments': payments,
      };
      final table = tables[path];
      if (table == null) throw StateError('Unhandled path: $path');
      if (request.method == 'POST') {
        final failParticipant = path.endsWith('/transaction_participants') &&
            failNextParticipantPost;
        final failPayment = path.endsWith('/payments') && failNextPaymentPost;
        if (failParticipant || failPayment) {
          if (failParticipant) failNextParticipantPost = false;
          if (failPayment) failNextPaymentPost = false;
          await _reply(httpRequest, request, 503, {
            'code': 'TEST_TRANSIENT_503',
            'message': 'Injected transient failure',
            'details': null,
            'hint': null,
          });
          return;
        }
        final ignored = request.headers['prefer']
                ?.split(',')
                .map((value) => value.trim())
                .contains('resolution=ignore-duplicates') ??
            false;
        final inserted = <Map<String, dynamic>>[];
        for (final row in request.jsonRows) {
          final id = row['id'] as String;
          // DO NOTHING returns [] on conflicts; non-ignore writes really mutate.
          if (table.containsKey(id) && ignored) continue;
          table[id] = Map<String, dynamic>.from(row);
          inserted.add({'id': id});
        }
        await _reply(httpRequest, request, 201, inserted);
        return;
      }
      if (request.method == 'GET') {
        final query = request.uri.queryParameters;
        final parentColumn = path.endsWith('/transaction_participants')
            ? 'transaction_id'
            : 'tab_id';
        final ids = _filterIds(query['id']!);
        final rows = [
          for (final row in table.values)
            if (ids.contains(row['id']) &&
                query[parentColumn] == 'eq.${row[parentColumn]}')
              {'id': row['id']},
        ];
        await _reply(httpRequest, request, 200, rows);
        return;
      }
      throw StateError('Unhandled method: ${request.method} $path');
    } catch (error) {
      errors.add(error.toString());
      await _reply(httpRequest, request, 400, {
        'code': 'FAKE_PROTOCOL_ERROR',
        'message': error.toString(),
      });
    }
  }

  Future<void> _reply(HttpRequest httpRequest, _RecordedRequest? request,
      int status, Object json) async {
    request?.responseStatus = status;
    request?.responseJson = json;
    httpRequest.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(json));
    await httpRequest.response.close();
  }
}
