import 'dart:io';

import 'package:path_provider/path_provider.dart';

const nativeCacheKey = 'tabby_cached_tabs_native-runtime-owner';
const nativeQueueKey = 'tabby_pending_ops_native-runtime-owner';
const nativeOperation = 'native-runtime-durable-operation';

Future<Directory> nativeFixtureDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/native-runtime-fixture');
}

List<Map<String, dynamic>> nativeHistoryFixture() => [
  for (var tab = 0; tab < 100; tab++)
    {
      'id': 'native-tab-$tab',
      'name': 'Synthetic native tab $tab',
      'netBalanceCentavos': 10000,
      'entries': [
        for (var row = 0; row < 100; row++)
          {
            'id': 'native-entry-$tab-$row',
            'date': DateTime.utc(
              2026,
              11,
              1,
            ).subtract(Duration(minutes: row)).toIso8601String(),
            'title': 'Synthetic encrypted native expense $tab-$row',
            'totalAmountCentavos': 100,
          },
      ],
    },
];
