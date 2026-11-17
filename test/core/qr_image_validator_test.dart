import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tabby/core/services/qr_image_validator.dart';
import 'package:tabby/core/services/receipt_attachment_service.dart';
import 'package:tabby/core/utils/qr_code_renderer.dart';
import 'package:tabby/features/payment_methods/application/payment_methods_provider.dart';
import 'package:tabby/features/payment_methods/domain/payment_method.dart';
import 'package:tabby/features/payment_methods/presentation/payment_methods_sheet.dart';
import 'package:tabby/features/tabs/data/supabase_tabby_repository.dart';

class _Methods extends Fake implements SupabaseTabbyRepository {
  @override
  Future<List<PaymentMethod>> fetchPaymentMethods(String ownerUserId) async =>
      [];
}

Future<Uint8List> _blank() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 300, 300), ui.Paint()..color = Colors.white);
  // High-frequency square patterns are not valid QR payloads.
  for (var y = 20; y < 280; y += 12) {
    for (var x = 20; x < 280; x += 12) {
      canvas.drawRect(ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 6, 6),
          ui.Paint()..color = Colors.black);
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 300);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('readable synthetic QR survives validation and optional crop', () async {
    final png =
        (await renderQrPng('https://example.com/synthetic-receiving-qr'))!;
    final prepared = await QrImageValidator.prepare(png);
    expect(prepared.bytes, isNotEmpty);
    // Validating again checks that the actual returned image remains readable.
    await expectLater(QrImageValidator.prepare(prepared.bytes), completes);
  });
  test('square patterned image without QR payload is rejected', () async {
    await expectLater(QrImageValidator.prepare(await _blank()),
        throwsA(isA<FormatException>()));
  });
  test('corrupt or empty images and oversize uploads are rejected', () async {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([1, 2, 3]),
      Uint8List(10 * 1024 * 1024 + 1)
    ]) {
      await expectLater(
          QrImageValidator.prepare(bytes), throwsA(isA<FormatException>()));
    }
  });
  test('plain account-number QR is rejected as a receiving QR', () async {
    final png = (await renderQrPng('09171234567'))!;
    await expectLater(
        QrImageValidator.prepare(png),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('account number'))));
  });
  testWidgets(
      'setup offers upload without account-string generator and catches picker failure',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        paymentMethodsProvider('owner').overrideWith((ref) =>
            PaymentMethodsNotifier(
                ownerUserId: 'owner', repository: _Methods()))
      ],
      child: const MaterialApp(
          home: Scaffold(body: PaymentMethodsSheet(ownerUserId: 'owner'))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Payment Method'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '09171234567');
    await tester.pumpAndSettle();
    expect(find.textContaining('Generate QR'), findsNothing);
    expect(find.textContaining('Regenerate QR'), findsNothing);
    final upload = find.text('Upload wallet QR image');
    expect(upload, findsOneWidget);
    ReceiptAttachmentService.debugPickImageOverride =
        (_) async => throw StateError('synthetic picker error');
    addTearDown(() => ReceiptAttachmentService.debugPickImageOverride = null);
    await tester.ensureVisible(upload);
    await tester.tap(upload);
    await tester.pumpAndSettle();
    expect(find.text('Unable to read QR image. Please try again.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'invalid selected image is rejected before a draft can contain it',
      (tester) async {
    final png = await tester.runAsync(_blank);
    ReceiptAttachmentService.debugPickImageOverride = (_) async =>
        XFile.fromData(png!, name: 'not-a-qr.png', mimeType: 'image/png');
    addTearDown(() => ReceiptAttachmentService.debugPickImageOverride = null);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        paymentMethodsProvider('owner').overrideWith((ref) =>
            PaymentMethodsNotifier(
                ownerUserId: 'owner', repository: _Methods()))
      ],
      child: const MaterialApp(
          home: Scaffold(body: PaymentMethodsSheet(ownerUserId: 'owner'))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Payment Method'));
    await tester.pumpAndSettle();
    final upload = find.text('Upload wallet QR image');
    await tester.ensureVisible(upload);
    await tester.runAsync(() async {
      await tester.tap(upload);
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.textContaining('No readable QR').evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('No readable QR'), findsOneWidget);
    expect(find.text('Readable QR image selected'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
