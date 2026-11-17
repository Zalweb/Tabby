import 'package:integration_test/integration_test.dart';

import '../test/features/auth_completion_scope_test.dart' as auth;

// Actual installed GoTrue client over device-loopback synthetic HTTP plus real
// form callbacks. Profile/ledger/storage controls remain explicit fixtures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const isolated = bool.fromEnvironment('TABBY_USB_TEST');
  if (!isolated) {
    throw StateError('Android auth tests require the isolated test package.');
  }
  auth.main();
}
