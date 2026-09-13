import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/tabby_colors.dart';
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
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Constrain to mobile phone viewport on desktop web
        if (kIsWeb) {
          final width = MediaQuery.of(context).size.width;
          if (width > 430) {
            return Container(
              color: const Color(0xFFE5E7EB), // Soft neutral desktop canvas
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: TabbyColors.backgroundLight,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 28,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          }
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
