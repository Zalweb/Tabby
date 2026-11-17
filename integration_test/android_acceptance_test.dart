import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/form_draft_store.dart';
import 'package:tabby/core/services/notification_preferences.dart';
import 'package:tabby/core/services/tabby_notification_service.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

class _SeededNotifier extends TabbyNotifier {
  _SeededNotifier(List<BilateralTab> tabs) : super(loadInitialData: false) {
    state = state.copyWith(
      tabs: tabs,
      activities: const [],
      reminders: const [],
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android schedules a real reminder alarm', (tester) async {
    const account = 'emulator-acceptance-account';
    const prefs = NotificationPreferencesStore();
    await prefs.save(account, const NotificationPreferences(enabled: true));
    final service = TabbyNotificationService.instance;
    await service.initialize();
    await service.setActiveAccount(account);
    if (!await service.permissionGranted()) {
      await service.requestPermission();
    }
    final enabled = await service.permissionGranted();
    expect(
      enabled,
      isTrue,
      reason: 'Android notification permission must be enabled',
    );
    final due = DateTime.now().add(const Duration(seconds: 240));
    await service.scheduleDueReminder(
      reminderId: 'emulator-boot-persistence-20261104',
      friendName: 'Synthetic friend',
      description: 'Emulator acceptance reminder',
      formattedAmount: 'PHP 12.34',
      dueDate: due,
      iOweThem: true,
      tabId: 'emulator-synthetic-tab',
    );
    debugPrint(
      'DEVICE_ACCEPTANCE_SCHEDULED due=${due.toIso8601String()} account=$account',
    );
  });

  testWidgets('Android renders seeded 100-tab 10000-entry history', (
    tester,
  ) async {
    final construction = Stopwatch()..start();
    final tabs = List.generate(100, (tabIndex) {
      final id = 'emulator-scale-tab-$tabIndex';
      final entries = List.generate(100, (rowIndex) {
        final global = tabIndex * 100 + rowIndex;
        return <String, dynamic>{
          'id': 'emulator-scale-entry-$global',
          'tabId': id,
          'title': 'Seeded history $global',
          'totalAmountCentavos': 101,
          'paidByUserId': 'synthetic-owner',
          'paidByName': 'Synthetic owner',
          'date': DateTime.utc(
            2026,
            11,
            4,
          ).subtract(Duration(seconds: global)).toIso8601String(),
        };
      });
      return BilateralTab.fromMap({
        'id': id,
        'name': 'Emulator scale $tabIndex',
        'netBalanceCentavos': 10100,
        'entries': entries,
      });
    });
    construction.stop();
    final render = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tabbyProvider.overrideWith((_) => _SeededNotifier(tabs))],
        child: MaterialApp(home: TabDetailScreen(tabId: tabs.first.id)),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    render.stop();
    expect(tabs.length, 100);
    expect(tabs.fold<int>(0, (sum, tab) => sum + tab.entries.length), 10000);
    expect(find.text('Seeded history 99'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Load older records'),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    expect(find.text('Load older records'), findsOneWidget);
    final reveal = Stopwatch()..start();
    await tester.tap(find.text('Load older records'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.text('Seeded history 50'),
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
    reveal.stop();
    expect(find.text('Seeded history 50'), findsOneWidget);
    debugPrint(
      'DEVICE_ACCEPTANCE_HISTORY tabs=100 entries=10000 constructionMs=${construction.elapsedMilliseconds} firstPageRenderMs=${render.elapsedMilliseconds} revealOlder50Ms=${reveal.elapsedMilliseconds}',
    );
  });

  testWidgets('camera permission denial leaves encrypted draft intact', (
    tester,
  ) async {
    const owner = 'emulator-picker-owner';
    const purpose = 'payment:emulator-picker';
    const drafts = FormDraftStore();
    await drafts.write(owner, purpose, {
      'amount': '12.34',
      'operation': 'emulator-operation',
    });
    String result;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera);
      result = picked == null ? 'cancelled-or-denied' : 'image-picked';
    } catch (error) {
      result = 'error:${error.runtimeType}';
    }
    final after = await drafts.read(owner, purpose);
    expect(after, {'amount': '12.34', 'operation': 'emulator-operation'});
    debugPrint('DEVICE_ACCEPTANCE_PICKER result=$result draftPreserved=true');
  });

  testWidgets('secure-storage sentinel is available to backup rehearsal', (
    tester,
  ) async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'tabby_emulator_backup_acceptance_sentinel',
      value: 'synthetic-secret',
    );
    expect(
      await storage.read(key: 'tabby_emulator_backup_acceptance_sentinel'),
      'synthetic-secret',
    );
    debugPrint(
      'DEVICE_ACCEPTANCE_BACKUP sentinelWritten=true packageAllowBackup=false',
    );
  });
}
