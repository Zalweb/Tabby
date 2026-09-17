import 'package:flutter/foundation.dart';

class AppState {
  static final ValueNotifier<bool> isAuthenticated = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> hasSeenOnboarding =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> profileCompletionRequired =
      ValueNotifier<bool>(false);
}
