import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/services/form_draft_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('synthetic draft persists after a real app process restart', (
    tester,
  ) async {
    final draft = await const FormDraftStore().read(
      'emulator-picker-owner',
      'payment:emulator-picker',
    );
    expect(draft, {'amount': '12.34', 'operation': 'emulator-operation'});
    debugPrint('DEVICE_ACCEPTANCE_DRAFT_RESTART preserved=true');
  });
}
