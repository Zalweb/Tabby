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
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
