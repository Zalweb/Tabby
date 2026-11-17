import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tabby/core/utils/qr_code_renderer.dart';

import '../test/features/receiving_session_scope_test.dart' as receiving;

// Native renderer/navigation with synthetic account/provider/clipboard ports.
// Images are generated locally and served only on this device's loopback.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const isolated = bool.fromEnvironment('TABBY_USB_TEST');
  if (!isolated) {
    throw StateError(
      'Android session tests require the isolated test package.',
    );
  }
  late HttpServer server;
  setUpAll(() async {
    final png = await renderQrPng(
      'https://example.invalid/android-session-fixture',
    );
    if (png == null) {
      throw StateError('Synthetic receiving PNG could not be rendered.');
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(png);
      await request.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));
  receiving.main(
    includeProviderUnitTests: false,
    qrUrlBuilder: () => 'http://127.0.0.1:${server.port}/synthetic-qr.png',
  );
}
