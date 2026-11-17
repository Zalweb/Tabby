import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabby/core/theme/tabby_theme.dart';
import 'package:tabby/features/tabs/application/tabby_providers.dart';
import 'package:tabby/features/tabs/domain/models.dart';

const warmOwner = TabbyUser(
  id: 'warm-owner',
  displayName: 'Sample Friend',
  email: 'sample@example.invalid',
  phone: '+639171234567',
);
const warmFriend = TabbyUser(
  id: 'warm-friend',
  displayName: 'Alex',
  email: '',
  phone: '',
);

TabbyNotifier warmLedger() {
  final notifier = TabbyNotifier(loadInitialData: false);
  notifier.state = notifier.state.copyWith(
    viewerUserId: warmOwner.id,
    activities: [],
    reminders: [],
    tabs: [
      BilateralTab(
        id: 'warm-tab',
        counterpart: warmFriend,
        netBalanceCentavos: 12500,
        itemCount: 0,
        entries: const [],
        lastUpdated: DateTime(2026, 11, 17),
      ),
    ],
  );
  return notifier;
}

Widget warmHost(
  Widget screen, {
  bool dark = false,
  double scale = 1,
  TabbyNotifier Function()? ledger,
}) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWith(
      (_) => CurrentUserNotifier(initialUser: warmOwner, autoLoad: false),
    ),
    tabbyProvider.overrideWith((_) => (ledger ?? warmLedger)()),
    userSettingsProvider.overrideWith(
      (_) => UserSettingsNotifier(
        userId: warmOwner.id,
        notificationsChanged: () async => false,
      ),
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? TabbyTheme.darkTheme : TabbyTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: screen,
  ),
);
