import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tabby/features/profile/application/profile_avatar_draft.dart';
import 'package:tabby/features/profile/presentation/profile_avatar.dart';
import 'package:tabby/features/profile/presentation/profile_avatar_sheet.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';

final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==');
const user = TabbyUser(
    id: 'synthetic-owner', displayName: 'Fixture Owner', email: '', phone: '');
ProfileAvatarDraft draft(
        {String owner = 'synthetic-owner',
        bool Function()? current,
        Future<XFile?> Function(ImageSource)? pick,
        Future<void> Function(String, Uint8List)? upload,
        Future<ProfileUpdateResult> Function(String)? save,
        FlutterSecureStorage storage = const FlutterSecureStorage(),
        bool realPrepare = false}) =>
    ProfileAvatarDraft(
        owner: owner,
        isCurrent: current ?? () => true,
        pick: pick ?? (_) async => XFile.fromData(png, name: 'synthetic.png'),
        upload: upload ?? (_, bytes) async {},
        save: save ?? (_) async => ProfileUpdateResult.success,
        storage: storage,
        prepare:
            realPrepare ? null : (bytes) async => Uint8List.fromList(bytes));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'photo bytes and immutable path survive restart and uncertain profile response',
      () async {
    final uploads = <String>[];
    final first = draft(
        upload: (path, bytes) async {
          uploads.add(path);
          expect(bytes, png);
        },
        save: (_) async => ProfileUpdateResult.failure);
    expect(await first.choose(ImageSource.gallery), isTrue);
    final path = first.path;
    expect(await first.apply(), isFalse);
    expect(first.hasDraft, isTrue);
    first.dispose();
    String? saved;
    final restarted = draft(upload: (path, bytes) async {
      uploads.add(path);
      expect(bytes, png);
    }, save: (reference) async {
      saved = reference;
      return ProfileUpdateResult.success;
    });
    await restarted.restore();
    expect(restarted.path, path);
    expect(restarted.bytes, png);
    expect(await restarted.apply(), isTrue);
    expect(uploads, [path, path]);
    expect(saved, 'avatar:$path');
    expect(await const FlutterSecureStorage().read(key: restarted.key), isNull);
    restarted.dispose();
  });
  test('picker cancellation does not upload or claim a change', () async {
    var calls = 0;
    final photo = draft(
        pick: (_) async => null,
        upload: (_, bytes) async {
          calls++;
        });
    expect(await photo.choose(ImageSource.camera), isFalse);
    expect(photo.hasDraft, isFalse);
    expect(photo.error, isNull);
    expect(calls, 0);
    photo.dispose();
  });
  test('failed upload never writes profile and keeps owned bytes', () async {
    var writes = 0;
    final photo = draft(
        upload: (_, bytes) async => throw StateError('offline'),
        save: (_) async {
          writes++;
          return ProfileUpdateResult.success;
        });
    await photo.choose(ImageSource.camera);
    expect(await photo.apply(), isFalse);
    expect(writes, 0);
    expect(photo.bytes, png);
    expect(photo.error, contains('kept'));
    photo.dispose();
  });
  test('late picker/upload cannot save into a different session', () async {
    var current = true, writes = 0;
    final upload = Completer<void>();
    final photo = draft(
        current: () => current,
        upload: (_, bytes) => upload.future,
        save: (_) async {
          writes++;
          return ProfileUpdateResult.success;
        });
    await photo.choose(ImageSource.gallery);
    final applying = photo.apply();
    current = false;
    upload.complete();
    expect(await applying, isFalse);
    expect(writes, 0);
    photo.dispose();
    final picker = Completer<XFile?>();
    current = true;
    final pending = draft(current: () => current, pick: (_) => picker.future);
    await pending.restore();
    final originalPath = pending.path;
    final choosing = pending.choose(ImageSource.camera);
    current = false;
    picker.complete(XFile.fromData(png));
    expect(await choosing, isFalse);
    expect(pending.path, originalPath);
    pending.dispose();
  });
  test('drafts are account scoped and corrupt data is not silently replaced',
      () async {
    final a = draft();
    await a.choose(ImageSource.gallery);
    final b = draft(owner: 'other-owner');
    await b.restore();
    expect(b.hasDraft, isFalse);
    await const FlutterSecureStorage()
        .write(key: b.key, value: 'corrupt fixture');
    b.dispose();
    final corrupted = draft(owner: 'other-owner');
    await corrupted.restore();
    expect(corrupted.error, contains('could not be read'));
    expect(await corrupted.choose(ImageSource.camera), isFalse);
    expect(await const FlutterSecureStorage().read(key: corrupted.key),
        'corrupt fixture');
    a.dispose();
    corrupted.dispose();
  });
  test('persistence failure preserves previous draft and prevents transport',
      () async {
    final storage = FailingAvatarStorage();
    final photo = draft(storage: storage);
    await photo.choose(ImageSource.gallery);
    final path = photo.path;
    storage.fail = true;
    expect(await photo.choose(ImageSource.camera), isFalse);
    expect(photo.path, path);
    photo.dispose();
    final restored = draft();
    await restored.restore();
    expect(restored.path, path);
    restored.dispose();
  });
  test('old acknowledged draft cleanup cannot erase a newer retained selection',
      () async {
    final ack = Completer<ProfileUpdateResult>();
    final old = draft(save: (_) => ack.future);
    await old.choose(ImageSource.gallery);
    final saving = old.apply();
    final newer = draft();
    await newer.restore();
    await newer.choose(ImageSource.camera);
    final newPath = newer.path;
    ack.complete(ProfileUpdateResult.success);
    expect(await saving, isTrue);
    final restored = draft();
    await restored.restore();
    expect(restored.path, newPath);
    old.dispose();
    newer.dispose();
    restored.dispose();
  });
  test('preset rejection keeps selected draft and awaits acknowledgment',
      () async {
    final ack = Completer<ProfileUpdateResult>();
    final photo = draft(save: (_) => ack.future);
    await photo.choose(ImageSource.gallery);
    final pending = photo.usePreset('');
    expect(photo.busy, isTrue);
    ack.complete(ProfileUpdateResult.failure);
    expect(await pending, isFalse);
    expect(photo.hasDraft, isTrue);
    photo.dispose();
  });
  test('real image preparation bounds dimensions and rejects invalid bytes',
      () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const Color(0xff007777), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1024, 512);
    final source = await image.toByteData(format: ui.ImageByteFormat.png);
    final prepared = await prepareAvatar(source!.buffer.asUint8List());
    final codec = await ui.instantiateImageCodec(prepared);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 512);
    expect(frame.image.height, 256);
    frame.image.dispose();
    codec.dispose();
    image.dispose();
    picture.dispose();
    await expectLater(prepareAvatar(Uint8List(0)), throwsFormatException);
    await expectLater(
        prepareAvatar(Uint8List(10 * 1024 * 1024 + 1)), throwsFormatException);
    await expectLater(
        prepareAvatar(Uint8List.fromList([1, 2, 3])), throwsA(anything));
  });
  testWidgets(
      'cancelled native picker leaves sheet open without success feedback',
      (tester) async {
    final photo = draft(pick: (_) async => null);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
              (_) => CurrentUserNotifier(initialUser: user, autoLoad: false))
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ProfileAvatarSheet(user: user, controller: photo)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileAvatarSheet), findsOneWidget);
    expect(find.text('Save photo'), findsNothing);
    expect(find.text('Profile photo saved.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'selected photo stays after upload failure and closes only on acknowledged save',
      (tester) async {
    var fail = true;
    final ack = Completer<ProfileUpdateResult>();
    final photo = draft(
        upload: (path, bytes) async {
          if (fail) throw StateError('Synthetic offline');
        },
        save: (_) => ack.future);
    await tester.runAsync(() => photo.choose(ImageSource.gallery));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
              (_) => CurrentUserNotifier(initialUser: user, autoLoad: false))
        ],
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => ProfileAvatarSheet(
                                user: user, controller: photo)),
                        child: const Text('Open photo')))))));
    await tester.tap(find.text('Open photo'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('Save photo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('kept here for retry'), findsOneWidget);
    expect(find.text('Profile photo saved.'), findsNothing);
    fail = false;
    await tester.tap(find.text('Save photo'));
    await tester.pump();
    expect(find.byType(ProfileAvatarSheet), findsOneWidget);
    ack.complete(ProfileUpdateResult.success);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileAvatarSheet), findsNothing);
    expect(find.text('Profile photo saved.'), findsOneWidget);
  });
  testWidgets(
      'photo download failure offers a retry and renders the retried bytes',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: ProfileAvatar(
            reference: 'avatar:one',
            name: 'Fixture',
            download: (_) async {
              if (++calls == 1) {
                throw StateError('Synthetic network failure');
              }
              return png;
            })));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.byTooltip('Retry profile photo'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets(
      'saved photo renders actual bytes and new reference clears previous image immediately',
      (tester) async {
    final next = Completer<Uint8List>();
    await tester.pumpWidget(MaterialApp(
        home: ProfileAvatar(
            reference: 'avatar:one', name: 'One', download: (_) async => png)));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        home: ProfileAvatar(
            reference: 'avatar:two',
            name: 'Two',
            download: (_) => next.future)));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    next.complete(png);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });
}

class FailingAvatarStorage extends FlutterSecureStorage {
  bool fail = false;
  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (fail) throw StateError('Synthetic storage failure');
    await super.write(
        key: key,
        value: value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions);
  }
}
