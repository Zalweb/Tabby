import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../config/supabase_config.dart';
import 'account_push_controller.dart';
import 'notification_preferences.dart';

class BackgroundReminderService {
  BackgroundReminderService._();
  static final instance = BackgroundReminderService._();
  static const _channel = MethodChannel('tabby/background_push');
  bool get supported => !kIsWeb && Platform.isAndroid;
  final readyNotifier = ValueNotifier<bool>(false);
  bool get ready => readyNotifier.value;
  set ready(bool value) {
    readyNotifier.value = value;
  }

  Future<void> Function()? onResume;
  void Function(Map<String, dynamic>)? onTap;
  late final _controller = AccountPushController(
    nativeScope: (account, binding) async {
      ready = false;
      if (supported) {
        await _channel.invokeMethod<void>(
            'setScope', {'account': account, 'binding': binding});
      }
    },
    token: () async =>
        supported ? await _channel.invokeMethod<String>('token') : null,
    register: (installation, binding, token) async {
      if (!SupabaseConfig.isInitialized ||
          SupabaseConfig.currentUserId == null) {
        throw StateError('No active account');
      }
      final result =
          await SupabaseConfig.client.rpc('register_push_device_v1', params: {
        'p_installation_id': installation,
        'p_binding_id': binding,
        'p_token': token,
        'p_reminders_enabled': true,
      });
      if (result != true) {
        throw StateError('Push registration not acknowledged');
      }
    },
    revoke: (installation, binding) async {
      if (!SupabaseConfig.isInitialized ||
          SupabaseConfig.currentUserId == null) {
        return;
      }
      await SupabaseConfig.client.rpc('revoke_push_device_v1',
          params: {'p_installation_id': installation, 'p_binding_id': binding});
    },
  );
  Future<void> initialize() async {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'tap' && call.arguments is Map) {
        _tap(Map<String, dynamic>.from(call.arguments as Map));
      } else if (call.method == 'resume' || call.method == 'tokenChanged') {
        try {
          await onResume?.call();
        } catch (_) {}
      }
    });
    final tap = await _channel.invokeMapMethod<String, dynamic>('initialTap');
    if (tap != null) _tap(tap);
  }

  void _tap(Map<String, dynamic> tap) {
    onTap?.call({'account': tap['account'], 'route': 'tab:${tap['tab']}'});
  }

  Future<void> bind(String? actor, Object session) async {
    ready = false;
    if (!supported) return;
    await _controller.bind(actor, session);
  }

  Future<void> synchronize({required bool permission}) async {
    ready = false;
    if (!supported || !SupabaseConfig.isInitialized) return;
    final session = SupabaseConfig.captureSession();
    final actor = _controller.account;
    if (session.accountId != actor) return;
    try {
      final preferences = actor == null
          ? const NotificationPreferences()
          : await const NotificationPreferencesStore().load(actor);
      if (!SupabaseConfig.isCurrentSession(session) ||
          _controller.account != actor) {
        return;
      }
      ready = await _controller.synchronize(
          enabled: permission && preferences.enabled && preferences.reminders);
    } catch (_) {
      // Local opt-in remains independent. UI reports remote unavailability and
      // foreground/resume retries; no token/credential details are logged.
      ready = false;
    }
  }

  Future<void> logout() => _controller.synchronize(enabled: false);
}
