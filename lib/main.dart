import 'features/auth/application/registration_flow.dart';
import 'core/theme/motion_preferences.dart';

import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/theme/tabby_palette.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/config/app_state.dart';
import 'core/config/supabase_config.dart';
import 'core/localization/app_localizations.dart';
import 'core/router/app_router.dart';
import 'core/services/tabby_notification_service.dart';
import 'core/services/receipt_attachment_service.dart';
import 'core/theme/tabby_theme.dart';
import 'core/widgets/biometric_gate.dart';
import 'core/widgets/startup_gate.dart';
import 'core/services/storage_recovery_service.dart';
import 'features/tabs/data/ledger_cache_storage.dart';
import 'features/app_update/domain/app_update_models.dart';
import 'features/app_update/presentation/app_update_prompt.dart';
import 'features/tabs/application/tabby_providers.dart';
import 'features/onboarding/application/first_launch_tour.dart';

Future<void> _refreshProfileCompletionState() => RegistrationFlow.refresh();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const StartupGate(
      initialize: _initializeApp,
      animateOpening: true,
      child: ProviderScope(child: TabbyApp(enableUpdateCheck: true)),
    ),
  );
}

bool _authListenerAttached = false;

Future<List<String>> _initializeApp() async {
  // Do this before mounting providers: failed recovery must never replay queues
  // or overwrite a key-bound database with a fresh empty cache.
  try {
    await const LedgerCacheStorage().read(key: 'tabby_startup_probe');
  } catch (_) {
    throw const LocalStorageUnavailable();
  }
  final notices = <String>[];
  try {
    await ReceiptAttachmentService.recovery.recover().timeout(
      const Duration(seconds: 10),
    );
  } catch (_) {
    notices.add(
      'An image draft could not be recovered. Reopen its form to retry.',
    );
  }

  // Restore the onboarding-seen marker from the sandbox preference (with a
  // one-time legacy secure read on non-iOS platforms). Optional: a failure
  // never blocks startup or sign-in.
  try {
    await FirstLaunchTour.restore().timeout(const Duration(seconds: 10));
  } catch (_) {
    notices.add('Saved preferences couldn’t be restored. You can continue.');
  }

  try {
    await TabbyNotificationService.instance.initialize().timeout(
      const Duration(seconds: 10),
    );
  } catch (_) {
    notices.add(
      'Notifications are unavailable. You can try again or continue.',
    );
  }
  {
    if (!SupabaseConfig.isInitialized) await SupabaseConfig.initialize();
    if (SupabaseConfig.isInitialized) {
      await TabbyNotificationService.instance
          .setActiveAccount(SupabaseConfig.currentUserId)
          .catchError((Object _) {
            notices.add(
              'Device alerts could not be reset. Please retry in settings.',
            );
          });
      if (SupabaseConfig.auth.currentUser != null) {
        AppState.registrationCheckPending.value = true;
        AppState.isAuthenticated.value = true;
        AppState.hasSeenOnboarding.value = true;
        // Best-effort sandbox marker; shares the in-flight write with tour
        // completion so an auth event racing the tour never overlaps saves.
        unawaited(FirstLaunchTour.persistSeenBestEffort());
        try {
          await _refreshProfileCompletionState().timeout(
            const Duration(seconds: 10),
          );
        } catch (_) {
          notices.add(
            'Your profile couldn’t be refreshed. You can continue and retry later.',
          );
        }
      }
      if (!_authListenerAttached) {
        _authListenerAttached = true;
        SupabaseConfig.auth.onAuthStateChange.listen((data) {
          final session = data.session;
          unawaited(
            TabbyNotificationService.instance
                .setActiveAccount(session?.user.id)
                .catchError((Object _) {}),
          );
          if (session != null) {
            final check = _refreshProfileCompletionState();
            AppState.isAuthenticated.value = true;
            AppState.hasSeenOnboarding.value = true;
            unawaited(FirstLaunchTour.persistSeenBestEffort());
            check.catchError((Object _) {});
          } else {
            AppState.isAuthenticated.value = false;
            RegistrationFlow.reset();
          }
        }, onError: (Object _, StackTrace __) {});
      }
    }
  }
  return notices;
}

final ValueNotifier<bool?> webDeviceFrameOverride = ValueNotifier<bool?>(null);

class TabbyApp extends ConsumerWidget {
  const TabbyApp({super.key, this.updateChecker, this.enableUpdateCheck});

  final AppUpdateChecker? updateChecker;
  final bool? enableUpdateCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    final reducedMotion =
        !settings.motionEnabled ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TabbyNotificationService.instance.markRouterReady(
        prepareTab: (actor, tab) async {
          if (!context.mounted || SupabaseConfig.currentUserId != actor) {
            return false;
          }
          final stamp = SupabaseConfig.captureSession();
          await ref.read(tabbyProvider.notifier).refreshTabs();
          if (!context.mounted || !SupabaseConfig.isCurrentSession(stamp)) {
            return false;
          }
          return ref.read(tabDetailProvider(tab))?.id == tab;
        },
      );
    });
    return MaterialApp.router(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Tabby',
      theme: TabbyMotion.theme(TabbyTheme.lightTheme, reducedMotion),
      darkTheme: TabbyMotion.theme(TabbyTheme.darkTheme, reducedMotion),
      themeMode: settings.darkModeEnabled ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(settings.languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeAnimationDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.unknown,
        },
      ),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();

        return ValueListenableBuilder<bool?>(
          valueListenable: webDeviceFrameOverride,
          builder: (context, frameOverride, _) {
            final isFramed = shouldRenderDeviceFrame(
              isWeb: kIsWeb,
              platform: defaultTargetPlatform,
              size: MediaQuery.of(context).size,
            );

            final appContent = isFramed
                ? IPhoneDeviceFrameWrapper(
                    onToggleFrame: () {
                      webDeviceFrameOverride.value = false;
                    },
                    child: content,
                  )
                : (kIsWeb
                      ? Stack(
                          children: [
                            content,
                            Positioned(
                              bottom: 16.0,
                              right: 16.0,
                              child: _buildFrameToggleBadge(
                                label: 'iPhone Frame',
                                icon: Icons.phone_iphone_rounded,
                                onTap: () {
                                  webDeviceFrameOverride.value = true;
                                },
                              ),
                            ),
                          ],
                        )
                      : content);

            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations:
                    !settings.motionEnabled ||
                    MediaQuery.disableAnimationsOf(context),
              ),
              child: BiometricGate(
                child: AppUpdatePrompt(
                  checker: updateChecker,
                  enabled: enableUpdateCheck ?? false,
                  navigatorKey: appRouter.routerDelegate.navigatorKey,
                  child: appContent,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Evaluates whether the desktop browser should simulate the iPhone hardware frame.
/// Yields directly to the full native screen on physical mobile devices or when frame override is false.
bool shouldRenderDeviceFrame({
  required bool isWeb,
  required TargetPlatform platform,
  required Size size,
}) {
  if (webDeviceFrameOverride.value != null) {
    return webDeviceFrameOverride.value!;
  }

  if (!isWeb) return false;

  // On actual physical mobile devices (iOS / Android), yield to full native screen
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.android) {
    return false;
  }

  // On narrow or short desktop browser windows (<= 500px in either dimension), yield to full native screen
  if (size.width <= 500 || size.height <= 500) {
    return false;
  }

  return true;
}

Widget _buildFrameToggleBadge({
  required String label,
  required IconData icon,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: const Color(0xE61F2937),
          borderRadius: BorderRadius.circular(24.0),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10.0,
              offset: const Offset(0, 3.0),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16.0, color: const Color(0xFFFBBF24)),
            const SizedBox(width: 8.0),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Realistic iPhone hardware frame wrapper for Flutter Web desktop mode.
class IPhoneDeviceFrameWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback? onToggleFrame;

  const IPhoneDeviceFrameWrapper({
    super.key,
    required this.child,
    this.onToggleFrame,
  });

  // Modern iPhone hardware geometry specs
  static const double frameWidth = 400.0;
  static const double frameHeight = 820.0;
  static const double bezelThickness = 10.0;
  static const double outerCornerRadius = 52.0;
  static const double innerCornerRadius = 44.0;
  static const double screenWidth = frameWidth - (bezelThickness * 2); // 380.0
  static const double screenHeight =
      frameHeight - (bezelThickness * 2); // 800.0

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).soft,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            TabbyPalette.of(context).canvas, // Warm desktop preview surround
            TabbyPalette.of(context).soft,
            TabbyPalette.of(context).border,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 24.0,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: _buildHardwareChassis(context),
              ),
            ),
          ),
          if (onToggleFrame != null)
            Positioned(
              top: 16.0,
              right: 16.0,
              child: _buildFrameToggleBadge(
                label: 'Full Screen',
                icon: Icons.fullscreen_rounded,
                onTap: onToggleFrame!,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHardwareChassis(BuildContext context) {
    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Hardware side buttons (Titanium finish)
          // Left: Action Button
          Positioned(
            left: -3.0,
            top: 115.0,
            child: _buildSideButton(width: 3.0, height: 26.0),
          ),
          // Left: Volume Up
          Positioned(
            left: -3.0,
            top: 155.0,
            child: _buildSideButton(width: 3.0, height: 48.0),
          ),
          // Left: Volume Down
          Positioned(
            left: -3.0,
            top: 218.0,
            child: _buildSideButton(width: 3.0, height: 48.0),
          ),
          // Right: Power / Side button
          Positioned(
            right: -3.0,
            top: 170.0,
            child: _buildSideButton(width: 3.0, height: 72.0),
          ),

          // Main iPhone Bezel Chassis
          Container(
            width: frameWidth,
            height: frameHeight,
            padding: const EdgeInsets.all(bezelThickness),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A), // Sleek dark titanium bezel
              borderRadius: BorderRadius.circular(outerCornerRadius),
              border: Border.all(
                color: const Color(
                  0xFF2C2C2C,
                ), // Chamfered metallic rim highlight
                width: 1.5,
              ),
              boxShadow: [
                // Ambient soft drop shadow
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 40.0,
                  spreadRadius: 2.0,
                  offset: const Offset(0, 20.0),
                ),
                // Depth grounding shadow
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14.0,
                  spreadRadius: 0.0,
                  offset: const Offset(0, 4.0),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerCornerRadius),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: screenWidth,
                height: screenHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // App Viewport with safe area insets for Dynamic Island & Home Bar
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: const Size(screenWidth, screenHeight),
                        padding: const EdgeInsets.only(top: 44.0, bottom: 28.0),
                        viewPadding: const EdgeInsets.only(
                          top: 44.0,
                          bottom: 28.0,
                        ),
                      ),
                      child: SizedBox(
                        width: screenWidth,
                        height: screenHeight,
                        child: child,
                      ),
                    ),

                    // Dynamic Island / Hardware Pill
                    const Positioned(
                      top: 11.0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: IgnorePointer(child: DynamicIslandWidget()),
                      ),
                    ),

                    // Bottom iOS Home Indicator
                    const Positioned(
                      bottom: 8.0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: IgnorePointer(child: IPhoneHomeIndicator()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideButton({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}

/// Floating Dynamic Island pill with speaker and camera lens hardware accents.
class DynamicIslandWidget extends StatelessWidget {
  const DynamicIslandWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 105.0,
      height: 28.0,
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        borderRadius: BorderRadius.circular(20.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4.0,
            offset: const Offset(0, 1.0),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Speaker / Sensor dot on left
          Positioned(
            left: 18.0,
            child: Container(
              width: 5.0,
              height: 5.0,
              decoration: const BoxDecoration(
                color: Color(0xFF111827),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Front-facing camera lens with subtle glare ring on right
          Positioned(
            right: 16.0,
            child: Container(
              width: 10.0,
              height: 10.0,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
              ),
              child: Center(
                child: Container(
                  width: 4.0,
                  height: 4.0,
                  decoration: const BoxDecoration(
                    color: Color(0xFF030712),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating iOS Home Indicator pill at bottom center.
class IPhoneHomeIndicator extends StatelessWidget {
  const IPhoneHomeIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130.0,
      height: 4.0,
      decoration: BoxDecoration(
        color: const Color(0xFF64748B).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(2.0),
      ),
    );
  }
}
