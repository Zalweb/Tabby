import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/features/tabs/data/ledger_cache_storage.dart';
import 'package:tabby/features/tabs/data/ledger_storage_factory_native.dart';
import 'package:tabby/features/tabs/data/tabby_local_cache.dart';
import 'package:tabby/features/tabs/data/mock_tabby_repository.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const nativeMe = MockTabbyRepository.currentUser;
const nativeOne = TabbyUser(
  id: 'one',
  displayName: 'One',
  email: '',
  phone: '',
);
const nativeTwo = TabbyUser(
  id: 'two',
  displayName: 'Two',
  email: '',
  phone: '',
);
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST') ||
      !const bool.fromEnvironment('TABBY_ENTRY_TEST')) {
    throw StateError(
      'Native storage fixture requires the isolated entry package.',
    );
  }
  testWidgets(
    'custom zero-payer shares survive encrypted native SQLite close and reopen',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'tabby-qa032-ledger-',
      );
      final storage = NativeLedgerCacheStorage(
        directory: () async => directory,
      );
      LedgerCacheStorage.debugOverride = storage;
      addTearDown(() async {
        LedgerCacheStorage.debugOverride = null;
        await storage.close();
      });
      final entry = LedgerEntry(
        id: 'native-expense',
        tabId: 'native-tab',
        title: 'Synthetic custom expense',
        category: ExpenseCategory.food,
        totalAmountCentavos: 45000,
        myShareCentavos: 0,
        counterpartShareCentavos: 45000,
        paidByUserId: nativeMe.id,
        paidByName: 'You',
        date: DateTime(2026, 11, 17),
        participants: [
          ParticipantShare(
            userId: nativeMe.id,
            name: 'You',
            shareAmountCentavos: 0,
            isPayer: true,
          ),
          ParticipantShare(
            userId: nativeOne.id,
            name: 'One',
            shareAmountCentavos: 15000,
          ),
          ParticipantShare(
            userId: nativeTwo.id,
            name: 'Two',
            shareAmountCentavos: 30000,
          ),
        ],
      );
      final tab = BilateralTab(
        id: 'native-tab',
        counterpart: nativeOne,
        isGroupTab: true,
        members: const [nativeMe, nativeOne, nativeTwo],
        netBalanceCentavos: 45000,
        itemCount: 1,
        entries: [entry],
        lastUpdated: DateTime(2026, 11, 17),
      );
      await tester.runAsync(() async {
        await TabbyLocalCache.saveTabs(
          [tab],
          userId: nativeMe.id,
          strict: true,
        );
        await storage.close();
        final restored = (await TabbyLocalCache.loadTabs(userId: nativeMe.id))!
            .single;
        expect(restored.id, tab.id);
        expect(restored.netBalanceCentavos, 45000);
        expect(
          restored.entries.single.participants.map(
            (p) => p.shareAmountCentavos,
          ),
          [0, 15000, 30000],
        );
        final header = await File('${directory.path}/tabby-ledger-v1.sqlite')
            .open();
        final bytes = await header.read(16);
        await header.close();
        expect(
          String.fromCharCodes(bytes),
          isNot(startsWith('SQLite format 3')),
        );
      });
    },
  );
}
