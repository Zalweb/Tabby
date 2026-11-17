// Manually orchestrated physical FCM fixture; never a normal app entry point.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('tabby/background_push');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('TABBY_USB_TEST')) {
    throw StateError('Only the isolated debug package may run FCM fixtures.');
  }
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Tabby isolated notification check')),
      ),
    ),
  );
  WidgetsBinding.instance.addObserver(_FixtureObserver());
  await _executeCommand();
}

class _FixtureObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _executeCommand();
  }
}

bool _busy = false;
Future<void> _executeCommand() async {
  if (_busy) return;
  _busy = true;
  final directory = await getApplicationDocumentsDirectory();
  final report = File('${directory.path}/qa018-fcm-result.json');
  try {
    final command = jsonDecode(
      await File('${directory.path}/qa018-fcm-command.json').readAsString(),
    ) as Map<String, dynamic>;
    final action = command['action'];
    final plugin = FlutterLocalNotificationsPlugin();
    if (action == 'seed') {
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      if (!uuid.hasMatch(command['account'] as String) ||
          !uuid.hasMatch(command['binding'] as String)) {
        throw StateError('Synthetic scope required');
      }
      await _channel.invokeMethod<void>('setScope', {
        'account': command['account'],
        'binding': command['binding'],
      });
      final token = await _channel.invokeMethod<String>('token');
      if (token == null || token.length < 20) {
        throw StateError('Real FCM registration unavailable');
      }
      await File('${directory.path}/qa018-fcm-token.json')
          .writeAsString(jsonEncode({'token': token}), flush: true);
    } else if (action == 'clear') {
      await _channel.invokeMethod<void>('setScope', {
        'account': null,
        'binding': null,
      });
    } else if (action != 'inspect') {
      throw StateError('Unknown isolated fixture action');
    }
    final active = await plugin.getActiveNotifications();
    await report.writeAsString(
      jsonEncode({
        'outcome': 'passed',
        'action': action,
        'notifications': active
            .map(
              (n) => {
                'tag': n.tag,
                'channel': n.channelId,
                'title': n.title,
                'body': n.body,
              },
            )
            .toList(),
        'tokens_logged': false,
      }),
      flush: true,
    );
  } catch (error) {
    // Never persist raw platform errors, registration tokens or configuration.
    await report.writeAsString(
      jsonEncode({
        'outcome': 'failed',
        'error_type': error.runtimeType.toString(),
        'tokens_logged': false,
      }),
      flush: true,
    );
  } finally {
    _busy = false;
  }
}
