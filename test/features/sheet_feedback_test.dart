import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/core/services/tabby_notification_banner.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';
import 'package:tabby/shared/widgets/tabby_feedback.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => SupabaseConfig.debugUserIdOverride = null);
  testWidgets(
    'inactive navigation branches cannot capture a visible-page message',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => TabbyFeedback.of(context).showSnackBar(
                      const SnackBar(content: Text('Visible page update')),
                    ),
                    child: const Text('Notify'),
                  ),
                ),
                const TickerMode(
                  enabled: false,
                  child: Offstage(
                    child: TabbyFeedbackScope(child: Text('Inactive branch')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Notify'));
      await tester.pumpAndSettle();
      expect(find.text('Visible page update').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Add validation is displayed on its full-screen form instead of behind it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: TabbyTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => AddExpenseModal.show(context),
                  child: const Text('Open Add'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Add'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add Person'));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      final message = find.text('Enter a name for the unregistered person.');
      expect(message, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tabby-fullscreen-form')),
          matching: message,
        ),
        findsOneWidget,
      );
      expect(message.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nested sheet owns feedback and popped save returns it to its parent',
    (tester) async {
      await tester.pumpWidget(
        _host(
          (context) => showTabbyBottomSheet<void>(
            context: context,
            builder: (parent) => TextButton(
              onPressed: () => showTabbyBottomSheet<void>(
                context: parent,
                builder: (child) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => TabbyFeedback.of(child).showSnackBar(
                        const SnackBar(content: Text('Fix this field')),
                      ),
                      child: const Text('Validate'),
                    ),
                    TextButton(
                      onPressed: () {
                        final feedback = TabbyFeedback.of(child);
                        Navigator.pop(child);
                        feedback.showSnackBar(
                          const SnackBar(content: Text('Saved successfully')),
                        );
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open nested'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open nested'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Validate'));
      await tester.pumpAndSettle();
      expect(find.text('Fix this field').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Saved successfully').hitTestable(), findsOneWidget);
      expect(find.text('Open nested').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss message'));
      await tester.pumpAndSettle();
      expect(find.text('Saved successfully'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('success after closing a sheet is visible on the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        (context) => showTabbyBottomSheet<void>(
          context: context,
          builder: (sheet) => TextButton(
            onPressed: () {
              final feedback = TabbyFeedback.of(sheet);
              Navigator.pop(sheet);
              feedback.showSnackBar(
                const SnackBar(content: Text('Saved on page')),
              );
            },
            child: const Text('Save'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved on page').hitTestable(), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a stale account callback cannot display feedback in the next session',
    (tester) async {
      TabbyFeedback? captured;
      SupabaseConfig.debugUserIdOverride = 'synthetic-first';
      await tester.pumpWidget(
        _host((context) {
          captured = TabbyFeedback.of(context);
        }),
      );
      await tester.tap(find.text('Open'));
      SupabaseConfig.debugUserIdOverride = 'synthetic-second';
      captured!.showSnackBar(
        const SnackBar(content: Text('Old account result')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old account result'), findsNothing);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'realtime notice stays visible above Add with keyboard and 200% text, dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.view.viewInsets = FakeViewPadding(
          bottom: 260 * tester.view.devicePixelRatio,
        );
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          _host(
            (context) => AddExpenseModal.show(context),
            dark: dark,
            scale: 2,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        TabbyNotificationBanner.show(
          title: 'New update',
          body: 'A synthetic tab has changed.',
        );
        await tester.pumpAndSettle();
        final notice = find.text('New update');
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('tabby-fullscreen-form')),
            matching: notice,
          ),
          findsOneWidget,
        );
        expect(notice.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(notice).dy, lessThan(460));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Dismiss message'));
        await tester.pumpAndSettle();
        expect(notice, findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Widget _host(
  void Function(BuildContext) open, {
  bool dark = false,
  double scale = 1,
}) => ProviderScope(
  child: MaterialApp(
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    theme: dark ? TabbyTheme.darkTheme : TabbyTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => open(context),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);
