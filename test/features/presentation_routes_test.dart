import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/tabs/presentation/add_expense_modal.dart';
import 'package:tabby/shared/widgets/tabby_feedback.dart';
import 'package:tabby/shared/widgets/receipt_source_sheet.dart';
import 'package:tabby/features/profile/presentation/profile_screen.dart';
import 'package:tabby/features/profile/presentation/profile_edit_sheet.dart';
import 'package:tabby/features/payment_methods/presentation/payment_methods_sheet.dart';
import 'package:tabby/features/tabs/presentation/payment_draft_form.dart';
import 'package:tabby/core/services/form_draft_store.dart';

import '../support/warm_design_fixture.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final action in ['remove', 'replace']) {
    testWidgets(
      '$action a prefilled contact cannot reuse its identity for a new person',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          warmHost(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => AddExpenseModal.show(
                    context,
                    initialCounterpartId: 'warm-tab',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
            ledger: () {
              final ledger = warmLedger();
              ledger.state = ledger.state.copyWith(
                tabs: [
                  ledger.state.tabs.first.copyWith(
                    isTabOnlyParticipant: true,
                    isLocalOnly: true,
                  ),
                ],
              );
              return ledger;
            },
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final selected = find.byType(Chip);
        expect(
          find.descendant(of: selected, matching: find.textContaining('Alex')),
          findsOneWidget,
        );
        if (action == 'remove') {
          await tester.ensureVisible(selected);
          await tester.tap(
            find.descendant(
              of: selected,
              matching: find.byIcon(Icons.close_rounded),
            ),
          );
          await tester.pumpAndSettle();
        }
        final name = find.byKey(const ValueKey('create-tab-unregistered-name'));
        await tester.ensureVisible(name);
        await tester.enterText(name, 'Taylor');
        await tester.ensureVisible(find.text('Add Person'));
        await tester.tap(find.text('Add Person'));
        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        final draft = await const FormDraftStore().read(
          warmOwner.id,
          'expense:warm-tab',
        );
        expect(draft!['unregistered'], 'Taylor');
        expect(draft['contact'], isNot(warmFriend.id));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final width in [390.0, 1280.0]) {
    testWidgets('compact sheets fill the horizontal viewport at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          (context) => showTabbyBottomSheet<void>(
            context: context,
            builder: (_) => const SizedBox(
              key: ValueKey('compact-content'),
              height: 160,
              child: Text('Quick choice'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(BottomSheet));
      expect(rect.left, closeTo(0, 0.1));
      expect(rect.width, closeTo(width, 0.1));
      expect(
        tester.getSize(find.byKey(const ValueKey('compact-content'))).width,
        closeTo(width, 0.1),
      );
      expect(rect.height, lessThan(844));
      await tester.binding.setSurfaceSize(Size(width + 120, 600));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('compact-content'))).width,
        closeTo(width + 120, 0.1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'Add opens an opaque full-screen route and nested choices return to it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host((context) => AddExpenseModal.show(context)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final form = find.byType(AddExpenseModal);
      expect(tester.getRect(form), const Rect.fromLTWH(0, 0, 390, 844));
      expect(find.text('Background').hitTestable(), findsNothing);
      await tester.ensureVisible(find.text('Add Person'));
      await tester.tap(find.text('Add Person'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a name for the unregistered person.').hitTestable(),
        findsOneWidget,
      );
      ReceiptSourceSheet.show(tester.element(form));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(ReceiptSourceSheet))).pop();
      await tester.pumpAndSettle();
      expect(form, findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss message'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Background').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'profile editing opens full screen and Appearance stays edge-to-edge, dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(warmHost(const ProfileScreen(), dark: dark));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit Profile'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          tester.getRect(find.byType(ProfileEditSheet)),
          const Rect.fromLTWH(0, 0, 1280, 800),
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Appearance'));
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        final heading = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Appearance'),
        );
        final surface = find
            .ancestor(of: heading, matching: find.byType(Material))
            .first;
        expect(tester.getRect(surface).left, closeTo(0, 0.1));
        expect(tester.getRect(surface).width, closeTo(1280, 0.1));
        expect(tester.getRect(surface).height, lessThan(800));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    for (final name in ['receiving', 'payment']) {
      testWidgets(
        '$name full-screen form fits keyboard and 200% text, dark=$dark',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 720));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          tester.view.viewInsets = FakeViewPadding(
            bottom: 260 * tester.view.devicePixelRatio,
          );
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpWidget(
            warmHost(
              Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showTabbyFormPage<void>(
                      context: context,
                      builder: (_) => name == 'receiving'
                          ? ReceivingMethodEditor(
                              ownerId: warmOwner.id,
                              onSave: (_) async => false,
                            )
                          : PaymentDraftForm(
                              tab: warmLedger().state.tabs.first,
                              isPayingMe: false,
                            ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
              dark: dark,
              scale: 2,
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            tester.getSize(find.byKey(const ValueKey('tabby-fullscreen-form'))),
            const Size(360, 720),
          );
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          if (name == 'receiving') {
            await tester.ensureVisible(find.text('Save Payment Method'));
            await tester.pumpAndSettle();
            expect(
              find.text('Save Payment Method').hitTestable(),
              findsOneWidget,
            );
            expect(
              tester.getBottomRight(find.text('Save Payment Method')).dy,
              lessThan(460),
            );
            expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

Widget _host(void Function(BuildContext) open) => ProviderScope(
  child: MaterialApp(
    theme: TabbyTheme.lightTheme,
    home: Scaffold(
      body: Column(
        children: [
          const Text('Background'),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ],
      ),
    ),
  ),
);
