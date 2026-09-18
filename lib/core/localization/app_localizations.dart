import 'package:flutter/material.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('fil')];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  String get profile => locale.languageCode == 'fil' ? 'Profile' : 'Profile';
  String get paymentMethods =>
      locale.languageCode == 'fil' ? 'Paraan ng Pagbayad' : 'Payment Methods';
  String get notifications =>
      locale.languageCode == 'fil' ? 'Mga Notification' : 'Notifications';
  String get appearance =>
      locale.languageCode == 'fil' ? 'Itsura' : 'Appearance';
  String get language => locale.languageCode == 'fil' ? 'Wika' : 'Language';
  String get syncAndOffline =>
      locale.languageCode == 'fil' ? 'Sync at Offline' : 'Sync & Offline';

  static const delegate = _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
        (supported) => supported.languageCode == locale.languageCode,
      );

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
