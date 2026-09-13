import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/tabby_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      child: TabbyApp(),
    ),
  );
}

class TabbyApp extends StatelessWidget {
  const TabbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tabby',
      theme: TabbyTheme.lightTheme,
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

        // Constrain to realistic iPhone hardware frame on desktop browser viewports
        if (shouldRenderDeviceFrame(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
          size: MediaQuery.of(context).size,
        )) {
          return IPhoneDeviceFrameWrapper(child: content);
        }

        return content;
      },
    );
  }
}

/// Evaluates whether the desktop browser should simulate the iPhone hardware frame.
/// Yields directly to the full native screen on physical mobile devices or narrow viewports.
bool shouldRenderDeviceFrame({
  required bool isWeb,
  required TargetPlatform platform,
  required Size size,
}) {
  if (!isWeb) return false;

  // On actual physical mobile devices (iOS / Android), yield to full native screen
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.android) {
    return false;
  }

  // On narrow browser windows (e.g. mobile emulation or resized window), yield to full native screen
  if (size.width <= 500 || size.height <= 500) {
    return false;
  }

  return true;
}

/// Realistic iPhone hardware frame wrapper for Flutter Web desktop mode.
class IPhoneDeviceFrameWrapper extends StatelessWidget {
  final Widget child;

  const IPhoneDeviceFrameWrapper({
    super.key,
    required this.child,
  });

  // Modern iPhone hardware geometry specs
  static const double frameWidth = 400.0;
  static const double frameHeight = 820.0;
  static const double bezelThickness = 10.0;
  static const double outerCornerRadius = 52.0;
  static const double innerCornerRadius = 44.0;
  static const double screenWidth = frameWidth - (bezelThickness * 2); // 380.0
  static const double screenHeight = frameHeight - (bezelThickness * 2); // 800.0

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF1F5F9), // Soft studio lighting highlight
            Color(0xFFE2E8F0), // Modern neutral studio backdrop
            Color(0xFFCBD5E1), // Grounding gradient shadow
          ],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: _buildHardwareChassis(context),
          ),
        ),
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
                color: const Color(0xFF2C2C2C), // Chamfered metallic rim highlight
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
                        viewPadding: const EdgeInsets.only(top: 44.0, bottom: 28.0),
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
                        child: IgnorePointer(
                          child: DynamicIslandWidget(),
                        ),
                      ),
                    ),

                    // Bottom iOS Home Indicator
                    const Positioned(
                      bottom: 8.0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: IgnorePointer(
                          child: IPhoneHomeIndicator(),
                        ),
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
                border: Border.all(
                  color: const Color(0xFF1E293B),
                  width: 1.0,
                ),
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
