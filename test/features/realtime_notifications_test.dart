import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/router/app_router.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/main.dart';
import 'package:tabby/shared/widgets/notification_center_sheet.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Real-Time Notifications Unit & Widget Tests', () {
    test('AppNotification serialization and unread count logic', () {
      final now = DateTime.now();
      final notif1 = AppNotification(
        id: 'n-1',
        recipientUserId: 'user-1',
        type: 'expense_added',
        relatedTabId: 'tab-1',
        title: 'New Expense Added',
        body: 'Lunch (₱250.00) was added to your tab.',
        isRead: false,
        createdAt: now,
      );

      final map = notif1.toMap();
      final deserialized = AppNotification.fromMap(map);

      expect(deserialized.id, 'n-1');
      expect(deserialized.title, 'New Expense Added');
      expect(deserialized.isRead, false);
      expect(deserialized.relatedTabId, 'tab-1');

      final notif2 = notif1.copyWith(isRead: true);
      expect(notif2.isRead, true);
    });

    testWidgets(
        'Home Dashboard displays Badge on Notification Bell when unread notifications exist',
        (tester) async {
      AppState.isAuthenticated.value = true;
      AppState.hasSeenOnboarding.value = true;
      appRouter.go('/home');

      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testNotification = AppNotification(
        id: 'test-n-1',
        recipientUserId: 'user-1',
        type: 'debt_created',
        relatedTabId: 'tab-123',
        title: 'New Tab Opened',
        body: 'Juan opened a new tab with you.',
        isRead: false,
        createdAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          tabbyProvider.overrideWith((ref) {
            final notifier = TabbyNotifier(loadInitialData: false);
            notifier.state = notifier.state.copyWith(
              notifications: [testNotification],
            );
            return notifier;
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TabbyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the badge with label '1' is displayed
      expect(find.text('1'), findsWidgets);
      expect(find.byIcon(Icons.notifications_active_rounded), findsWidgets);
    });

    testWidgets(
        'NotificationCenterSheet displays ALERTS & NOTIFICATIONS section and Mark all read button',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testNotification = AppNotification(
        id: 'notif-payment',
        recipientUserId: 'user-1',
        type: 'payment_submitted',
        relatedTabId: 'tab-999',
        title: 'Payment Received',
        body: 'A payment of ₱500.00 was recorded on your tab.',
        isRead: false,
        createdAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          tabbyProvider.overrideWith((ref) {
            final notifier = TabbyNotifier(loadInitialData: false);
            notifier.state = notifier.state.copyWith(
              notifications: [testNotification],
            );
            return notifier;
          }),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: NotificationCenterSheet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('1 unread notification'), findsOneWidget);
      expect(find.text('ALERTS & NOTIFICATIONS'), findsOneWidget);
      expect(find.text('Payment Received'), findsOneWidget);
      expect(find.text('A payment of ₱500.00 was recorded on your tab.'), findsOneWidget);
      expect(find.text('Mark all read'), findsWidgets);

      // Tap Mark all read
      await tester.tap(find.text('Mark all read').first);
      await tester.pumpAndSettle();

      // Verify notifications marked as read
      final state = container.read(tabbyProvider);
      expect(state.unreadNotificationCount, 0);
      expect(state.notifications.first.isRead, true);
    });
  });
}
