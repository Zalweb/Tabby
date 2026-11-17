import 'package:flutter/material.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);
  final Locale locale;
  static const supportedLocales = <Locale>[Locale('en')];
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  String get profile => 'Profile';
  String get paymentMethods => 'Payment Methods';
  String get notifications => 'Notifications';
  String get appearance => 'Appearance';
  String get language => 'Language';
  String get syncAndOffline => 'Sync & Offline';
  static const delegate = _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';
  @override
  Future<AppLocalizations> load(Locale locale) async =>
      const AppLocalizations(Locale('en'));
  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
