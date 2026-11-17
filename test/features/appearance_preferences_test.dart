import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/localization/app_localizations.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/core/services/appearance_preferences.dart';
import 'package:tabby/core/theme/tabby_colors.dart';
import 'package:tabby/core/theme/tabby_palette.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/features/profile/presentation/profile_edit_sheet.dart';
import 'package:tabby/features/tabs/presentation/my_tabs_screen.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart'
    as receiving;
import 'package:tabby/features/payment_methods/presentation/receiving_qr_image.dart';
import 'package:tabby/shared/widgets/tabby_mascot_widget.dart';
import 'package:tabby/main.dart';

const me = TabbyUser(
  id: 'theme-owner',
  displayName: 'Fixture Owner',
  email: 'fixture@example.invalid',
  phone: '+639171234567',
);
const friend = TabbyUser(
  id: 'theme-friend',
  displayName: 'Fixture Friend',
  email: '',
  phone: '',
);
UserSettingsNotifier settings({
  FlutterSecureStorage? storage,
  String owner = 'theme-owner',
}) => UserSettingsNotifier(
  userId: owner,
  storage: storage,
  notificationsChanged: () async => false,
);
TabbyNotifier ledger() {
  final notifier = TabbyNotifier(loadInitialData: false);
  notifier.state = notifier.state.copyWith(
    viewerUserId: me.id,
    activities: [],
    reminders: [],
    tabs: [
      BilateralTab(
        id: 'theme-tab',
        counterpart: friend,
        netBalanceCentavos: 12345,
        itemCount: 0,
        entries: const [],
        lastUpdated: DateTime(2026, 11, 1),
      ),
    ],
  );
  return notifier;
}

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Widget host(
  Widget child, {
  bool dark = false,
  bool reduced = true,
  double scale = 1,
  UserSettingsNotifier? preferences,
}) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWith(
      (_) => CurrentUserNotifier(initialUser: me, autoLoad: false),
    ),
    tabbyProvider.overrideWith((_) => ledger()),
    userSettingsProvider.overrideWith((_) => preferences ?? settings()),
  ],
  child: MaterialApp(
    theme: dark ? TabbyTheme.darkTheme : TabbyTheme.lightTheme,
    builder: (context, content) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(scale),
      ),
      child: content!,
    ),
    home: child,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (call) async => null,
        );
    FlutterSecureStorage.setMockInitialValues({});
    SupabaseConfig.debugUserIdOverride = null;
  });
  tearDown(() => SupabaseConfig.debugUserIdOverride = null);
  test('legacy unsupported currency/language never change the PHP English contract', () async {
    FlutterSecureStorage.setMockInitialValues({
      'tabby_theme-owner_currency_code': 'USD',
      'tabby_theme-owner_language_code': 'fil',
    });
    final notifier = settings();
    await notifier.ready;
    expect(notifier.state.currencyCode, 'PHP');
    expect(notifier.state.languageCode, 'en');
    await expectLater(
      notifier.update(currencyCode: 'USD'),
      throwsArgumentError,
    );
    await expectLater(
      notifier.update(languageCode: 'fil'),
      throwsArgumentError,
    );
    expect(AppLocalizations.supportedLocales, [const Locale('en')]);
    notifier.dispose();
  });
  test('appearance restores only scoped legacy values and persists one atomic envelope', () async {
    FlutterSecureStorage.setMockInitialValues({
      'tabby_theme-owner_motion_enabled': 'false',
      'tabby_theme-owner_dark_mode_enabled': 'true',
      'tabby_dark_mode_enabled': 'true',
    });
    final notifier = settings();
    await notifier.ready;
    expect(notifier.state.motionEnabled, isFalse);
    expect(notifier.state.darkModeEnabled, isTrue);
    expect(await notifier.setAppearancePreferences(motion: true), isTrue);
    notifier.dispose();
    final restored = settings();
    await restored.ready;
    expect(restored.state.motionEnabled, isTrue);
    expect(restored.state.darkModeEnabled, isTrue);
    final raw = await const FlutterSecureStorage().read(
      key: AppearancePreferencesStore.key(me.id),
    );
    expect(jsonDecode(raw!), {'motion': true, 'dark': true});
    final other = settings(owner: 'other-owner');
    await other.ready;
    expect(other.state.darkModeEnabled, isFalse);
    restored.dispose();
    other.dispose();
  });
  test(
    'failed appearance persistence keeps previous state and retry succeeds',
    () async {
      final storage = ControlledStorage();
      final notifier = settings(storage: storage);
      await notifier.ready;
      storage.fail = true;
      expect(
        await notifier.setAppearancePreferences(dark: true, motion: false),
        isFalse,
      );
      expect(notifier.state.darkModeEnabled, isFalse);
      expect(notifier.state.motionEnabled, isTrue);
      expect(notifier.state.appearanceError, contains('previous settings'));
      storage.fail = false;
      expect(await notifier.setAppearancePreferences(dark: true), isTrue);
      expect(notifier.state.appearanceError, isNull);
      notifier.dispose();
    },
  );
  test(
    'queued appearance changes merge with the last acknowledged preferences',
    () async {
      final storage = ControlledStorage()
        ..blocked = Completer<void>()
        ..started = Completer<void>();
      final notifier = settings(storage: storage);
      await notifier.ready;
      final dark = notifier.setAppearancePreferences(dark: true);
      await storage.started!.future;
      final motion = notifier.setAppearancePreferences(motion: false);
      expect(notifier.state.darkModeEnabled, isFalse);
      storage.blocked!.complete();
      expect(await dark, isTrue);
      expect(await motion, isTrue);
      expect(notifier.state.darkModeEnabled, isTrue);
      expect(notifier.state.motionEnabled, isFalse);
      notifier.dispose();
    },
  );
  test(
    'late old-account save cannot update a different account state',
    () async {
      SupabaseConfig.debugUserIdOverride = me.id;
      final storage = ControlledStorage()
        ..blocked = Completer<void>()
        ..started = Completer<void>();
      final notifier = settings(storage: storage);
      await notifier.ready;
      final pending = notifier.setAppearancePreferences(dark: true);
      await storage.started!.future;
      SupabaseConfig.debugUserIdOverride = 'other-owner';
      storage.blocked!.complete();
      expect(await pending, isFalse);
      expect(notifier.state.darkModeEnabled, isFalse);
      final other = settings(owner: 'other-owner');
      await other.ready;
      expect(other.state.darkModeEnabled, isFalse);
      notifier.dispose();
      other.dispose();
    },
  );
  test('corrupt appearance is optional and cannot bypass or block security initialization', () async {
    FlutterSecureStorage.setMockInitialValues({
      AppearancePreferencesStore.key(me.id): '{"motion":"bad","dark":true}',
    });
    final notifier = settings();
    await notifier.ready;
    expect(notifier.state.isLoaded, isTrue);
    expect(notifier.state.appearanceError, isNotNull);
    expect(await notifier.setAppearancePreferences(dark: true), isTrue);
    expect(notifier.state.appearanceError, isNull);
    notifier.dispose();
  });
  for (final palette in [TabbyPalette.light, TabbyPalette.dark]) {
    test(
      '${palette == TabbyPalette.dark ? 'dark' : 'light'} text and financial text contrast',
      () {
        for (final background in [
          palette.surface,
          palette.canvas,
          palette.mint,
          palette.blueTint,
          palette.pendingTint,
        ]) {
          for (final text in [
            palette.text,
            palette.secondaryText,
            palette.mutedText,
            palette.link,
            palette.positiveText,
          ]) {
            expect(contrast(text, background), greaterThanOrEqualTo(4.5));
          }
        }
        expect(
          contrast(palette.warningText, palette.pendingTint),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(TabbyColors.brandDarkTeal, TabbyColors.brandEmerald),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }
  for (final dark in [false, true]) {
    for (final entry in <String, Widget>{
      'home': const HomeDashboardScreen(),
      'profile': const ProfileScreen(),
      'tabs': const MyTabsScreen(),
      'detail': const TabDetailScreen(tabId: 'theme-tab'),
      'expense': const Scaffold(body: AddExpenseModal()),
    }.entries) {
      testWidgets(
        '${entry.key} renders ${dark ? 'dark' : 'light'} surfaces and text without layout errors',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(host(entry.value, dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final palette = dark ? TabbyPalette.dark : TabbyPalette.light;
          expect(
            Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
            dark ? Brightness.dark : Brightness.light,
          );
          final fills = [
            ...tester
                .widgetList<Material>(find.byType(Material))
                .map((m) => m.color),
            ...tester
                .widgetList<Container>(find.byType(Container))
                .map(
                  (c) =>
                      c.color ??
                      (c.decoration is BoxDecoration
                          ? (c.decoration as BoxDecoration).color
                          : null),
                ),
          ];
          expect(
            fills,
            contains(anyOf(palette.surface, palette.canvas, palette.mint)),
          );
          if (entry.key == 'profile') {
            final label = tester.widget<Text>(find.text('Fixture Owner'));
            expect(label.style?.color, palette.text);
          }
          if (entry.key == 'expense') {
            expect(
              tester.widget<Text>(find.text('1')).style?.color,
              TabbyColors.brandInk,
            );
          }
        },
      );
    }
    testWidgets(
      'profile editor uses the actual ${dark ? 'dark' : 'light'} canvas for implicit Material',
      (tester) async {
        await tester.pumpWidget(
          host(
            const Scaffold(body: ProfileEditSheet(user: me)),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        final material = find
            .descendant(
              of: find.byType(ProfileEditSheet),
              matching: find.byType(Material),
            )
            .first;
        expect(
          Theme.of(tester.element(material)).canvasColor,
          dark ? TabbyPalette.dark.surface : TabbyPalette.light.surface,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'QR quiet zone stays white with original provider in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        const method = receiving.PaymentMethod(
          id: 'synthetic-method',
          ownerUserId: 'theme-owner',
          provider: 'other',
          displayName: 'Synthetic QR',
          accountLabel: '',
          qrStoragePath: 'theme-owner/synthetic.png',
          qrUrl: 'https://example.invalid/synthetic.png',
        );
        await tester.pumpWidget(
          host(
            Scaffold(
              body: ReceivingQrImage(method: method, reload: () async => null),
            ),
            dark: dark,
          ),
        );
        final quiet = find
            .ancestor(of: find.byType(Image), matching: find.byType(ColoredBox))
            .first;
        expect(tester.widget<ColoredBox>(quiet).color, Colors.white);
        expect(find.byType(ColorFiltered), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'appearance controls retain failure, then apply a persisted dark selection',
    (tester) async {
      final storage = ControlledStorage();
      final controlled = settings(storage: storage);
      await controlled.ready;
      await tester.pumpWidget(
        host(const ProfileScreen(), preferences: controlled),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Appearance'));
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      storage.fail = true;
      await tester.tap(find.text('Dark mode'));
      await tester.pumpAndSettle();
      expect(controlled.state.darkModeEnabled, isFalse);
      expect(find.textContaining('previous settings'), findsOneWidget);
      storage.fail = false;
      await tester.tap(find.text('Dark mode'));
      await tester.pumpAndSettle();
      expect(controlled.state.darkModeEnabled, isTrue);
      expect(find.textContaining('previous settings'), findsNothing);
    },
  );
  testWidgets(
    'Profile omits static preferences while the real appearance sheet respects reduced motion',
    (tester) async {
      await tester.pumpWidget(host(const ProfileScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Currency Precision'), findsNothing);
      expect(find.text('Language'), findsNothing);
      await tester.ensureVisible(find.text('Appearance'));
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.text('Light mode')))!;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(find.textContaining('Filipino'), findsNothing);
      expect(find.byType(RadioListTile<bool>), findsNothing);
    },
  );
  testWidgets(
    'system reduced motion wins over enabled preference in the actual app',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      AppState.hasSeenOnboarding.value = true;
      AppState.isAuthenticated.value = true;
      AppState.profileCompletionRequired.value = false;
      appRouter.go('/profile');
      final prefs = settings();
      await prefs.ready;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userSettingsProvider.overrideWith((_) => prefs),
            currentUserProvider.overrideWith(
              (_) => CurrentUserNotifier(initialUser: me, autoLoad: false),
            ),
            tabbyProvider.overrideWith((_) => ledger()),
          ],
          child: const TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        MediaQuery.disableAnimationsOf(
          tester.element(find.byType(ProfileScreen)),
        ),
        isTrue,
      );
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .themeAnimationDuration,
        Duration.zero,
      );
      expect(await prefs.setAppearancePreferences(dark: true), isTrue);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(ProfileScreen))).brightness,
        Brightness.dark,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.person_rounded)).color,
        TabbyColors.brandInk,
      );
      expect(
        tester.widget<Text>(find.text('Fixture Owner')).style?.color,
        TabbyPalette.dark.text,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      AppState.isAuthenticated.value = false;
    },
  );
  testWidgets(
    'production ambient animation stops immediately and remains static under reduced motion',
    (tester) async {
      Widget mascot(bool reduced, MascotEmotion emotion) => host(
        Scaffold(
          body: TabbyMascotWidget(emotion: emotion, animateAmbient: true),
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(mascot(false, MascotEmotion.celebrating));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(mascot(true, MascotEmotion.celebrating));
      await tester.pumpAndSettle();
      final transforms = tester
          .widgetList<Transform>(find.byType(Transform))
          .map((t) => t.transform.storage.toList())
          .toList();
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widgetList<Transform>(find.byType(Transform))
            .map((t) => t.transform.storage.toList())
            .toList(),
        transforms,
      );
      await tester.pumpWidget(mascot(true, MascotEmotion.userOwes));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('theme screenshot evidence uses synthetic profile only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        host(
          RepaintBoundary(key: boundary, child: const ProfileScreen()),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final directory = Directory('.dart_tool/theme-artifacts');
        await directory.create(recursive: true);
        await File('${directory.path}/profile-${dark ? 'dark' : 'light'}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });
}

class ControlledStorage extends FlutterSecureStorage {
  bool fail = false;
  Completer<void>? blocked, started;
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key.endsWith('_appearance_v1')) {
      if (started != null && !started!.isCompleted) started!.complete();
      if (blocked != null) await blocked!.future;
      if (fail) throw StateError('Synthetic appearance persistence failure');
    }
    await super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}
