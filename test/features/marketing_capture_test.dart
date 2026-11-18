import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/features/auth/presentation/login_screen.dart';
import 'package:tabby/features/home/presentation/home_dashboard_screen.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';
import 'package:tabby/features/tabs/presentation/tab_detail_screen.dart';

import '../support/warm_design_fixture.dart';

const marketingOwner = TabbyUser(
  id: 'mkt-owner',
  displayName: 'Maria Santos',
  email: 'maria@example.invalid',
  phone: '+639171234567',
);
const marketingFriend = TabbyUser(
  id: 'mkt-friend',
  displayName: 'Alex Reyes',
  email: '',
  phone: '',
);
const marketingFriendTwo = TabbyUser(
  id: 'mkt-friend-2',
  displayName: 'Bea Cruz',
  email: '',
  phone: '',
);
const marketingFriendThree = TabbyUser(
  id: 'mkt-friend-3',
  displayName: 'Carlo Diaz',
  email: '',
  phone: '',
);

final marketingNow = DateTime(2026, 11, 18, 18, 30);

TabbyNotifier marketingLedger() {
  final date = marketingNow;
  final expense = LedgerEntry(
    id: 'mkt-expense-1',
    tabId: 'mkt-tab',
    title: 'Beach house',
    category: ExpenseCategory.other,
    totalAmountCentavos: 480000,
    myShareCentavos: 240000,
    counterpartShareCentavos: 240000,
    paidByUserId: marketingOwner.id,
    paidByName: marketingOwner.displayName,
    date: date.subtract(const Duration(days: 2)),
    status: TransactionStatus.acknowledged,
    participants: const [
      ParticipantShare(
        userId: 'mkt-owner',
        name: 'Maria Santos',
        shareAmountCentavos: 240000,
        isPayer: true,
      ),
      ParticipantShare(
        userId: 'mkt-friend',
        name: 'Alex Reyes',
        shareAmountCentavos: 240000,
      ),
    ],
  );
  final expenseTwo = LedgerEntry(
    id: 'mkt-expense-2',
    tabId: 'mkt-tab',
    title: 'Van transfer',
    category: ExpenseCategory.other,
    totalAmountCentavos: 200000,
    myShareCentavos: 100000,
    counterpartShareCentavos: 100000,
    paidByUserId: marketingFriend.id,
    paidByName: marketingFriend.displayName,
    date: date.subtract(const Duration(days: 1)),
    status: TransactionStatus.acknowledged,
    participants: const [
      ParticipantShare(
        userId: 'mkt-friend',
        name: 'Alex Reyes',
        shareAmountCentavos: 100000,
        isPayer: true,
      ),
      ParticipantShare(
        userId: 'mkt-owner',
        name: 'Maria Santos',
        shareAmountCentavos: 100000,
      ),
    ],
  );
  final payment = LedgerEntry(
    id: 'mkt-payment',
    tabId: 'mkt-tab',
    title: 'Payment confirmed',
    category: ExpenseCategory.other,
    totalAmountCentavos: 80000,
    myShareCentavos: 0,
    counterpartShareCentavos: 0,
    paidByUserId: marketingFriend.id,
    paidByName: marketingFriend.displayName,
    date: date.subtract(const Duration(hours: 3)),
    status: TransactionStatus.settled,
    isPayment: true,
    payer: const PartyRef(kind: PartyKind.user, id: 'mkt-friend'),
    recipient: const PartyRef(kind: PartyKind.user, id: 'mkt-owner'),
  );
  final coffee = LedgerEntry(
    id: 'mkt-coffee',
    tabId: 'mkt-coffee',
    title: 'Coffee run',
    category: ExpenseCategory.other,
    totalAmountCentavos: 48000,
    myShareCentavos: 24000,
    counterpartShareCentavos: 24000,
    paidByUserId: marketingFriendTwo.id,
    paidByName: marketingFriendTwo.displayName,
    date: date.subtract(const Duration(hours: 6)),
    status: TransactionStatus.acknowledged,
    participants: const [
      ParticipantShare(
        userId: 'mkt-friend-2',
        name: 'Bea Cruz',
        shareAmountCentavos: 24000,
        isPayer: true,
      ),
      ParticipantShare(
        userId: 'mkt-owner',
        name: 'Maria Santos',
        shareAmountCentavos: 24000,
      ),
    ],
  );
  final n = TabbyNotifier(loadInitialData: false);
  n.state = n.state.copyWith(
    viewerUserId: marketingOwner.id,
    tabs: [
      BilateralTab(
        id: 'mkt-tab',
        counterpart: marketingFriend,
        isGroupTab: true,
        groupName: 'Siargao Weekend',
        members: const [marketingOwner, marketingFriend],
        netBalanceCentavos: 60000,
        itemCount: 3,
        entries: [expense, expenseTwo, payment],
        lastUpdated: date,
      ),
      BilateralTab(
        id: 'mkt-coffee',
        counterpart: marketingFriendTwo,
        netBalanceCentavos: -24000,
        itemCount: 1,
        entries: [coffee],
        lastUpdated: date.subtract(const Duration(hours: 6)),
      ),
      BilateralTab(
        id: 'mkt-clear',
        counterpart: marketingFriendThree,
        netBalanceCentavos: 0,
        itemCount: 0,
        entries: const [],
        lastUpdated: date.subtract(const Duration(days: 4)),
      ),
    ],
    reminders: [
      UpcomingReminder(
        id: 'mkt-reminder',
        tabId: 'mkt-tab',
        friendName: 'Alex Reyes',
        description: 'Siargao Weekend',
        amountCentavos: 60000,
        dueDate: date.add(const Duration(days: 1)),
        isIWhoOwe: false,
        counterparty: const PartyRef(kind: PartyKind.user, id: 'mkt-friend'),
      ),
    ],
    activities: [
      TabbyActivity(
        id: 'mkt-activity-1',
        actorName: 'Alex Reyes',
        description: 'Payment confirmed',
        amountCentavos: 80000,
        timestamp: date.subtract(const Duration(hours: 3)),
      ),
      TabbyActivity(
        id: 'mkt-activity-2',
        actorName: 'Maria Santos',
        description: 'Added Beach house',
        amountCentavos: 480000,
        timestamp: date.subtract(const Duration(days: 2)),
      ),
      TabbyActivity(
        id: 'mkt-activity-3',
        actorName: 'You',
        description: 'Tab cleared',
        amountCentavos: 0,
        timestamp: date.subtract(const Duration(days: 4)),
      ),
    ],
  );
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
  });
  const capture = bool.fromEnvironment('TABBY_CAPTURE_MARKETING');
  setUpAll(() async {
    if (!capture) return;
    final dir = Platform.environment['TABBY_UI_FONT_DIR'];
    if (dir == null) {
      throw StateError('Set TABBY_UI_FONT_DIR for readable preview capture');
    }
    final interPath =
        Platform.environment['TABBY_MARKETING_FONT'] ?? '$dir/roboto-regular.ttf';
    for (final font in [
      ('Inter', interPath),
      ('MaterialIcons', '$dir/materialicons-regular.otf'),
    ]) {
      final loader = FontLoader(font.$1)
        ..addFont(
          Future.value(
            ByteData.sublistView(await File(font.$2).readAsBytes()),
          ),
        );
      await loader.load();
    }
  });

  Future<void> captureScreen(WidgetTester tester, String name) async {
    if (!capture) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final rendered = await boundary.toImage(pixelRatio: 2);
      final bytes =
          (await rendered.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
      final file = File('build_artifacts/marketing/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      rendered.dispose();
    });
  }

  final screens = <String, Widget>{
    'login': const LoginScreen(),
    'home': HomeDashboardScreen(now: () => marketingNow),
    'detail': const TabDetailScreen(tabId: 'mkt-tab'),
    'profile': const ProfileScreen(),
  };

  for (final dark in [false, true]) {
    for (final entry in screens.entries) {
      testWidgets('capture marketing ${entry.key} ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          warmHost(
            RepaintBoundary(
              key: const ValueKey('capture'),
              child: entry.value,
            ),
            dark: dark,
            ledger: marketingLedger,
            owner: marketingOwner,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureScreen(tester, '${entry.key}-${dark ? 'dark' : 'light'}');
      });
    }
  }
}
