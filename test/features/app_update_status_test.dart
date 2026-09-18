import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tabby/features/app_update/data/app_update_service.dart';
import 'package:tabby/features/app_update/domain/app_update_models.dart';

void main() {
  test('update status distinguishes an up-to-date release', () async {
    final service = AppUpdateService(
      client: MockClient((_) async => http.Response(
            '{"tag_name":"v1.0.1","html_url":"https://github.com/Zalweb/Tabby/releases/tag/v1.0.1","assets":[]}',
            200,
          )),
      installedVersionLoader: () async => const AppVersion(1, 0, 1, 2),
    );

    final result = await service.checkStatus();

    expect(result.status, AppUpdateStatus.upToDate);
    expect(result.update, isNull);
  });

  test('update status exposes a newer release', () async {
    final service = AppUpdateService(
      client: MockClient((_) async => http.Response(
            '{"tag_name":"v1.0.2","html_url":"https://github.com/Zalweb/Tabby/releases/tag/v1.0.2","assets":[]}',
            200,
          )),
      installedVersionLoader: () async => const AppVersion(1, 0, 1, 2),
    );

    final result = await service.checkStatus();

    expect(result.status, AppUpdateStatus.updateAvailable);
    expect(result.update?.release.version, const AppVersion(1, 0, 2));
  });
}
