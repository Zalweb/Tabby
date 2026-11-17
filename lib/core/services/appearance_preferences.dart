import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppearancePreferences {
  const AppearancePreferences({this.motion = true, this.dark = false});
  final bool motion, dark;
  Map<String, bool> toMap() => {'motion': motion, 'dark': dark};
}

/// One atomic value per account. Reads wait for preceding writes, including
/// those from an older notifier instance during a same-account relogin.
class AppearancePreferencesStore {
  const AppearancePreferencesStore(
      {this.storage = const FlutterSecureStorage()});
  final FlutterSecureStorage storage;
  static final _work = <String, Future<void>>{};
  static String key(String owner) => 'tabby_${owner}_appearance_v1';
  Future<T> _run<T>(String owner, Future<T> Function() task) async {
    final result = (_work[owner] ?? Future<void>.value()).then((_) => task());
    final barrier =
        result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    _work[owner] = barrier;
    try {
      return await result;
    } finally {
      if (identical(_work[owner], barrier)) _work.remove(owner);
    }
  }

  Future<AppearancePreferences> load(String owner) => _run(owner, () async {
        final raw = await storage.read(key: key(owner));
        if (raw != null) {
          final value = jsonDecode(raw) as Map<String, dynamic>;
          if (value['motion'] is! bool || value['dark'] is! bool) {
            throw const FormatException('Invalid appearance preferences');
          }
          return AppearancePreferences(
              motion: value['motion'] as bool, dark: value['dark'] as bool);
        }
        final motion = await storage.read(key: 'tabby_${owner}_motion_enabled');
        final dark =
            await storage.read(key: 'tabby_${owner}_dark_mode_enabled');
        if ([motion, dark].any(
            (value) => value != null && value != 'true' && value != 'false')) {
          throw const FormatException('Invalid legacy appearance preferences');
        }
        return AppearancePreferences(
            motion: motion != 'false', dark: dark == 'true');
      });
  Future<void> save(String owner, AppearancePreferences value) => _run(owner,
      () => storage.write(key: key(owner), value: jsonEncode(value.toMap())));
}
