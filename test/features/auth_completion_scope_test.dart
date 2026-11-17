import 'package:tabby/features/auth/application/registration_flow.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/auth/presentation/login_screen.dart';
import 'package:tabby/features/auth/presentation/signup_screen.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/application/tabby_state.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/shared/widgets/tabby_button.dart';

const _a = '51000000-0000-4000-8000-000000000001';
const _b = '51000000-0000-4000-8000-000000000002';
const _user = TabbyUser(id: _a, displayName: 'Synthetic', email: '', phone: '');

Map<String, Object> _session(String id) {
  String part(Object x) =>
      base64UrlEncode(utf8.encode(jsonEncode(x))).replaceAll('=', '');
  return {
    'access_token':
        '${part({'alg': 'HS256'})}.${part({'sub': id, 'role': 'authenticated', 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})}.synthetic',
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 86400,
    'user': {
      'id': id,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'fixture@example.invalid',
      'app_metadata': <String, Object>{},
      'user_metadata': <String, Object>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
}

class _Pause {
  final entered = Completer<void>(), release = Completer<void>();
  Future<void> hold() {
    entered.complete();
    return release.future;
  }
}

class _GooglePort extends GoogleSignInPlatform {
  String mode = 'browser';
  @override
  Future<void> initWithParams(SignInInitParameters params) async {}
  @override
  Future<GoogleSignInUserData?> signIn() async {
    if (mode == 'cancel') return null;
    if (mode == 'browser') {
      throw PlatformException(code: 'synthetic_native_unavailable');
    }
    return GoogleSignInUserData(
      email: 'fixture@example.invalid',
      id: 'synthetic-google',
    );
  }

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth = true,
  }) async => mode == 'no-token'
      ? GoogleSignInTokenData()
      : GoogleSignInTokenData(
          idToken: 'synthetic-id-token',
          accessToken: 'synthetic-access-token',
        );
}

class _BrowserPort extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;
  bool opens = true;
  int launches = 0;
  String? redirect;
  _Pause? pause;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches++;
    redirect = Uri.parse(url).queryParameters['redirect_to'];
    await pause?.hold();
    return opens;
  }
}

class _User extends CurrentUserNotifier {
  _User(this.pause) : super(initialUser: _user, autoLoad: false);
  final _Pause? pause;
  @override
  Future<void> loadFromSupabase() async {
    await pause?.hold();
  }
}

class _Ledger extends StateNotifier<TabbyDashboardState>
    implements TabbyNotifier {
  _Ledger(this.pause, this.onRefresh)
    : super(const TabbyDashboardState(tabs: [], activities: [], reminders: []));
  final _Pause? pause;
  final VoidCallback onRefresh;
  @override
  Future<bool> refreshTabs() async {
    onRefresh();
    await pause?.hold();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingPreferenceMap extends MapBase<String, String> {
  final _data = <String, String>{};
  @override
  String? operator [](Object? key) => _data[key];
  @override
  void operator []=(String key, String value) {
    if (key == 'tabby_has_seen_onboarding') {
      throw PlatformException(code: 'synthetic_preference_failure');
    }
    _data[key] = value;
  }

  @override
  void clear() => _data.clear();
  @override
  Iterable<String> get keys => _data.keys;
  @override
  String? remove(Object? key) => _data.remove(key);
}

class _LocalOnly extends HttpOverrides {
  _LocalOnly(this.port);
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      if (uri.host != '127.0.0.1' || uri.port != port) {
        throw StateError(
          'External network forbidden in auth completion fixture',
        );
      }
      return 'DIRECT';
    };
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late HttpOverrides? oldOverrides;
  late Completer<void> profileEntered, profileRelease;
  late Future<void> completion;
  _Pause? intermediate;
  String? pauseAt;
  var ledgerRefreshCalls = 0;
  late GoogleSignInPlatform oldGoogle;
  late UrlLauncherPlatform oldBrowser;
  late _GooglePort google;
  late _BrowserPort browser;
  StreamController<AuthState>? googleEvents;
  setUpAll(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['none'],
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      Object body = <Object>[];
      if (request.uri.path == '/auth/v1/token' ||
          request.uri.path == '/auth/v1/signup') {
        body = _session(_a);
      } else if (request.uri.path == '/auth/v1/user') {
        body = _session(SupabaseConfig.currentUserId ?? _a)['user']!;
      } else if (request.uri.path == '/rest/v1/users') {
        if (!profileEntered.isCompleted) profileEntered.complete();
        await profileRelease.future;
        body = [
          {'display_name': 'Synthetic', 'phone': '+639991234567'},
        ];
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    oldOverrides = HttpOverrides.current;
    HttpOverrides.global = _LocalOnly(server.port);
    await SupabaseConfig.initialize(
      url: 'http://127.0.0.1:${server.port}',
      anonKey: 'synthetic-anon',
      debug: false,
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    await server.close(force: true);
    HttpOverrides.global = oldOverrides;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
  });
  setUp(() async {
    RegistrationFlow.reset();
    googleEvents = null;
    oldGoogle = GoogleSignInPlatform.instance;
    oldBrowser = UrlLauncherPlatform.instance;
    google = _GooglePort();
    browser = _BrowserPort();
    GoogleSignInPlatform.instance = google;
    UrlLauncherPlatform.instance = browser;
    profileEntered = Completer<void>();
    profileRelease = Completer<void>();
    intermediate = null;
    pauseAt = null;
    ledgerRefreshCalls = 0;
    AppState.isAuthenticated.value = false;
    AppState.hasSeenOnboarding.value = true;
    AppState.profileCompletionRequired.value = true;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() async {
    await googleEvents?.close();
    if (browser.pause != null && !browser.pause!.release.isCompleted) {
      browser.pause!.release.complete();
    }
    GoogleSignInPlatform.instance = oldGoogle;
    UrlLauncherPlatform.instance = oldBrowser;
    if (intermediate != null && !intermediate!.release.isCompleted) {
      intermediate!.release.complete();
    }
    if (!profileRelease.isCompleted) profileRelease.complete();
    await SupabaseConfig.client.removeAllChannels();
    await SupabaseConfig.auth.signOut(scope: SignOutScope.local);
  });

  Future<GoRouter> open(
    WidgetTester tester,
    bool signup, {
    bool useGoogle = false,
  }) async {
    if (!signup && !useGoogle) google.mode = 'native';
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => signup
              ? const SignUpScreen()
              : LoginScreen(googleAuthEvents: googleEvents?.stream),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Protected home')),
        ),
        GoRoute(
          path: '/complete-profile',
          builder: (_, _) =>
              const Scaffold(body: Text('Complete profile gate')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
            (_) => _User(pauseAt == 'user' ? intermediate : null),
          ),
          tabbyProvider.overrideWith(
            (_) => _Ledger(
              pauseAt == 'ledger' ? intermediate : null,
              () => ledgerRefreshCalls++,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    if (useGoogle) return router;
    if (!signup) {
      final button = tester.widget<TabbyButton>(find.byWidgetPredicate((w) => w is TabbyButton && w.label == 'Continue with Google'));
      await tester.runAsync(() async {
        completion = Function.apply(button.onPressed!, const []) as Future<void>;
        await (intermediate?.entered.future ?? profileEntered.future).timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      return router;
    }
    final fields = find.byType(TextField);
    final values = signup
        ? [
            'Synthetic',
            'fixture@example.invalid',
            '09991234567',
            'Synthetic-pass-123!',
            'Synthetic-pass-123!',
          ]
        : ['fixture@example.invalid', 'Synthetic-pass-123!'];
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
    await tester.ensureVisible(
      find.text(signup ? 'Create account' : 'Sign in'),
    );
    await tester.runAsync(() async {
      final button = tester.widget<TabbyButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TabbyButton &&
              widget.label == (signup ? 'Create account' : 'Sign in'),
        ),
      );
      // Invoke the real form callback and retain its terminal Future, so no
      // assertion depends on a guessed network delay after releasing HTTP.
      completion = Function.apply(button.onPressed!, const []) as Future<void>;
      await (intermediate?.entered.future ?? profileEntered.future).timeout(
        const Duration(seconds: 5),
      );
    });
    await tester.pump();
    return router;
  }

  Future<void> pressGoogle(WidgetTester tester) async {
    final button = tester.widget<TabbyButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TabbyButton && widget.label == 'Continue with Google',
      ),
    );
    await tester.runAsync(() async {
      completion = Function.apply(button.onPressed!, const []) as Future<void>;
      if (google.mode == 'native') {
        await profileEntered.future.timeout(const Duration(seconds: 5));
      } else if (browser.pause != null) {
        await browser.pause!.entered.future.timeout(const Duration(seconds: 5));
      } else {
        await completion.timeout(const Duration(seconds: 5));
      }
    });
    await tester.pump();
  }

  testWidgets(
    'Google browser launch is pending without a false sign-in error',
    (tester) async {
      final router = await open(tester, false, useGoogle: true);
      await pressGoogle(tester);
      expect(
        find.text('Finish signing in in your browser, then return to Tabby.'),
        findsOneWidget,
      );
      expect(find.textContaining('still in progress'), findsNothing);
      expect(AppState.isAuthenticated.value, isFalse);
      expect(profileEntered.isCompleted, isFalse);
      expect(ledgerRefreshCalls, 0);
      expect(browser.launches, 1);
      expect(
        browser.redirect,
        const bool.fromEnvironment('TABBY_USB_TEST')
            ? 'io.supabase.tabby.usbtest://login-callback'
            : 'io.supabase.tabby://login-callback',
      );
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(
        tester
            .widget<TabbyButton>(
              find.byWidgetPredicate(
                (w) => w is TabbyButton && w.label == 'Continue with Google',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Google browser launch failure is actionable and clears busy state',
    (tester) async {
      browser.opens = false;
      await open(tester, false, useGoogle: true);
      await pressGoogle(tester);
      expect(
        find.text('Google sign-in failed. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.text('Finish signing in in your browser, then return to Tabby.'),
        findsNothing,
      );
      expect(AppState.isAuthenticated.value, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Google missing ID token attempts the browser only once', (
    tester,
  ) async {
    google.mode = 'no-token';
    browser.opens = false;
    await open(tester, false, useGoogle: true);
    await pressGoogle(tester);
    expect(browser.launches, 1);
    expect(
      find.text('Google sign-in failed. Please try again.'),
      findsOneWidget,
    );
    expect(AppState.isAuthenticated.value, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Google native cancellation does not open a browser or authenticate',
    (tester) async {
      google.mode = 'cancel';
      await open(tester, false, useGoogle: true);
      await pressGoogle(tester);
      expect(browser.launches, 0);
      expect(AppState.isAuthenticated.value, isFalse);
      expect(find.textContaining('Google sign-in failed'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> googleCallbackError(WidgetTester tester) async {
    await tester.runAsync(() async {
      googleEvents!.addError(
        const AuthException(
          'Synthetic provider failure with private details',
          code: 'server_error',
          statusCode: 'unexpected_failure',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  testWidgets('Google callback failure replaces pending browser instructions', (
    tester,
  ) async {
    googleEvents = await tester.runAsync(
      () async => StreamController<AuthState>.broadcast(),
    );
    await open(tester, false, useGoogle: true);
    await pressGoogle(tester);
    expect(googleEvents!.hasListener, isTrue);
    await googleCallbackError(tester);
    expect(
      find.text('Google sign-in failed. Please try again.'),
      findsOneWidget,
    );
    expect(
      find.text('Finish signing in in your browser, then return to Tabby.'),
      findsNothing,
    );
    expect(find.textContaining('private details'), findsNothing);
    expect(AppState.isAuthenticated.value, isFalse);
    expect(profileEntered.isCompleted, isFalse);
    expect(googleEvents!.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Google callback failure before launch acknowledgment stays actionable',
    (tester) async {
      googleEvents = await tester.runAsync(
        () async => StreamController<AuthState>.broadcast(),
      );
      browser.pause = await tester.runAsync(() async => _Pause());
      await open(tester, false, useGoogle: true);
      await pressGoogle(tester);
      await googleCallbackError(tester);
      browser.pause!.release.complete();
      await tester.runAsync(
        () => completion.timeout(const Duration(seconds: 5)),
      );
      await tester.pump();
      expect(
        find.text('Google sign-in failed. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.text('Finish signing in in your browser, then return to Tabby.'),
        findsNothing,
      );
      expect(AppState.isAuthenticated.value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disposed Google form stops observing callback failures', (
    tester,
  ) async {
    googleEvents = await tester.runAsync(
      () async => StreamController<AuthState>.broadcast(),
    );
    await open(tester, false, useGoogle: true);
    await pressGoogle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(googleEvents!.hasListener, isFalse);
    await googleCallbackError(tester);
    expect(tester.takeException(), isNull);
    expect(AppState.isAuthenticated.value, isFalse);
  });

  testWidgets('Google callback failure cannot change a later account session', (
    tester,
  ) async {
    googleEvents = await tester.runAsync(
      () async => StreamController<AuthState>.broadcast(),
    );
    await open(tester, false, useGoogle: true);
    await pressGoogle(tester);
    await tester.runAsync(
      () => SupabaseConfig.auth.recoverSession(jsonEncode(_session(_b))),
    );
    await googleCallbackError(tester);
    expect(SupabaseConfig.currentUserId, _b);
    expect(find.text('Google sign-in failed. Please try again.'), findsNothing);
    expect(profileEntered.isCompleted, isFalse);
    expect(googleEvents!.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'disposed Google browser handoff cannot authenticate or set form state',
    (tester) async {
      browser.pause = await tester.runAsync(() async => _Pause());
      await open(tester, false, useGoogle: true);
      await pressGoogle(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      browser.pause!.release.complete();
      await tester.runAsync(
        () => completion.timeout(const Duration(seconds: 5)),
      );
      expect(AppState.isAuthenticated.value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final obsolete in [false, true]) {
    testWidgets(
      'Google native completion ${obsolete ? 'rejects an obsolete session' : 'uses its acknowledged session'}',
      (tester) async {
        google.mode = 'native';
        final router = await open(tester, false, useGoogle: true);
        await pressGoogle(tester);
        await tester.runAsync(() async {
          if (obsolete) {
            await SupabaseConfig.auth.signOut(scope: SignOutScope.local);
          }
          profileRelease.complete();
          await completion.timeout(const Duration(seconds: 5));
        });
        await tester.pumpAndSettle();
        expect(AppState.isAuthenticated.value, !obsolete);
        expect(browser.launches, 0);
        expect(
          router.routeInformationProvider.value.uri.path,
          obsolete ? '/login' : '/home',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final signup in [false, true]) {
    for (final stage in ['user', 'ledger']) {
      testWidgets(
        '${signup ? 'signup' : 'login'} stops after obsolete $stage load',
        (tester) async {
          intermediate = await tester.runAsync(() async => _Pause());
          pauseAt = stage;
          final router = await open(tester, signup);
          await tester.runAsync(
            () => SupabaseConfig.auth.recoverSession(jsonEncode(_session(_b))),
          );
          AppState.isAuthenticated.value = false;
          AppState.profileCompletionRequired.value = true;
          intermediate!.release.complete();
          await tester.runAsync(
            () => completion.timeout(const Duration(seconds: 5)),
          );
          await tester.pumpAndSettle();
          expect(ledgerRefreshCalls, stage == 'user' ? 0 : 1);
          expect(profileEntered.isCompleted, isFalse);
          expect(AppState.isAuthenticated.value, isFalse);
          expect(AppState.profileCompletionRequired.value, isTrue);
          expect(router.routeInformationProvider.value.uri.path, '/login');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
    for (final storageFailure in [false, true]) {
      testWidgets(
        '${signup ? 'signup' : 'login'} completes with ${storageFailure ? 'failed' : 'working'} onboarding storage',
        (tester) async {
          if (storageFailure) {
            FlutterSecureStorage.setMockInitialValues(_FailingPreferenceMap());
          }
          final router = await open(tester, signup);
          await tester.runAsync(() async {
            profileRelease.complete();
            await completion.timeout(const Duration(seconds: 5));
          });
          await tester.pumpAndSettle();
          expect(AppState.isAuthenticated.value, isTrue);
          expect(AppState.profileCompletionRequired.value, isFalse);
          expect(router.routeInformationProvider.value.uri.path, '/home');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
    for (final change in ['signout', 'other-account', 'same-account-relogin']) {
      testWidgets(
        '${signup ? 'signup' : 'login'} ignores profile completion after $change',
        (tester) async {
          final router = await open(tester, signup);
          await tester.runAsync(() async {
            await SupabaseConfig.auth.signOut(scope: SignOutScope.local);
            if (change != 'signout') {
              await SupabaseConfig.auth.recoverSession(
                jsonEncode(_session(change == 'other-account' ? _b : _a)),
              );
            }
          });
          AppState.isAuthenticated.value = false;
          AppState.profileCompletionRequired.value = true;
          profileRelease.complete();
          await tester.runAsync(
            () => completion.timeout(const Duration(seconds: 5)),
          );
          await tester.pumpAndSettle();
          expect(AppState.isAuthenticated.value, isFalse);
          expect(AppState.profileCompletionRequired.value, isTrue);
          expect(router.routeInformationProvider.value.uri.path, '/login');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets('disposed signup cannot reauthenticate after signout', (
    tester,
  ) async {
    await open(tester, true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => SupabaseConfig.auth.signOut(scope: SignOutScope.local),
    );
    AppState.isAuthenticated.value = false;
    AppState.profileCompletionRequired.value = true;
    profileRelease.complete();
    await tester.runAsync(() => completion.timeout(const Duration(seconds: 5)));
    await tester.pumpAndSettle();
    expect(AppState.isAuthenticated.value, isFalse);
    expect(AppState.profileCompletionRequired.value, isTrue);
  });
}
