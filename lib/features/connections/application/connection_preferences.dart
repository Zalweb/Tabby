import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/supabase_config.dart';
import '../../tabs/application/tabby_providers.dart';

@immutable
class ConnectionPreferences {
  const ConnectionPreferences(
      {this.revision = 0,
      this.nicknames = const {},
      this.archived = const {},
      this.loaded = false,
      this.busy = false,
      this.error});
  final int revision;
  final Map<String, String> nicknames;
  final Set<String> archived;
  final bool loaded, busy;
  final String? error;
  Map<String, dynamic> toMap() => {
        'revision': revision,
        'nicknames': nicknames,
        'archived_tab_ids': archived.toList()..sort()
      };
  factory ConnectionPreferences.fromMap(Map<String, dynamic> map) {
    final revision = map['revision'] as int;
    final nicknames = Map<String, String>.from(map['nicknames'] as Map);
    final archived = (map['archived_tab_ids'] as List).cast<String>().toSet();
    if (revision < 0 || nicknames.values.any((n) => n.length > 80)) {
      throw const FormatException('Invalid connections');
    }
    return ConnectionPreferences(
        revision: revision,
        nicknames: Map.unmodifiable(nicknames),
        archived: Set.unmodifiable(archived),
        loaded: true);
  }
  ConnectionPreferences withStatus({bool? busy, String? error}) =>
      ConnectionPreferences(
          revision: revision,
          nicknames: nicknames,
          archived: archived,
          loaded: loaded,
          busy: busy ?? this.busy,
          error: error);
}

class ConnectionPreferencesNotifier
    extends StateNotifier<ConnectionPreferences> {
  ConnectionPreferencesNotifier(
      {required this.owner,
      required this.current,
      this.readRemote,
      this.changeRemote,
      this.storage = const FlutterSecureStorage()})
      : super(const ConnectionPreferences()) {
    ready = reload();
  }
  final String owner;
  final bool Function() current;
  final Future<Map<String, dynamic>> Function()? readRemote;
  final Future<Map<String, dynamic>> Function(
      String operation, Map<String, dynamic> command)? changeRemote;
  final FlutterSecureStorage storage;
  ConnectionPreferences get snapshot => state;
  late final Future<void> ready;
  String get key => 'tabby_${owner}_connections_v1';
  String? _pendingCommand, _pendingOperation;
  bool get active => mounted && current();
  static final _storageWork = <String, Future<void>>{};
  Future<T> _stored<T>(Future<T> Function() work) async {
    final previous = _storageWork[owner] ?? Future<void>.value();
    final result = previous.then((_) => work());
    final barrier =
        result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    _storageWork[owner] = barrier;
    try {
      return await result;
    } finally {
      if (identical(_storageWork[owner], barrier)) _storageWork.remove(owner);
    }
  }

  Future<void> reload() async {
    if (!active || state.busy) return;
    state = state.withStatus(busy: true);
    try {
      String? raw;
      try {
        raw = await _stored(() => storage.read(key: key));
        if (!active) return;
        if (raw != null) {
          state = ConnectionPreferences.fromMap(
                  jsonDecode(raw) as Map<String, dynamic>)
              .withStatus(busy: true);
        }
      } catch (_) {
        if (readRemote == null) rethrow;
      }
      if (readRemote != null) {
        final remote = ConnectionPreferences.fromMap(await readRemote!());
        if (!active) return;
        try {
          await _stored(
              () => storage.write(key: key, value: jsonEncode(remote.toMap())));
        } catch (_) {}
        if (!active) return;
        state = remote;
      } else if (raw == null) {
        state = const ConnectionPreferences(loaded: true);
      } else {
        state = state.withStatus(busy: false);
      }
    } catch (_) {
      if (active) {
        state = state.withStatus(
            busy: false,
            error:
                'Connections could not be refreshed. Showing the retained view.');
      }
    }
  }

  Future<bool> change(String action, String target, {String? nickname}) async {
    await ready;
    if (!active || state.busy || !state.loaded) return false;
    if (!const {'nickname', 'archive', 'restore', 'unfriend'}
            .contains(action) ||
        target.isEmpty ||
        (action == 'nickname' && nickname == null) ||
        ((action == 'nickname' || action == 'unfriend') && target == owner)) {
      return false;
    }
    if (nickname != null && nickname.trim().length > 80) {
      state = state.withStatus(
          error: 'Use at most 80 characters for a private nickname.');
      return false;
    }
    final before = state;
    state = state.withStatus(busy: true);
    final command = <String, dynamic>{
      'owner_id': owner,
      'action': action,
      'target_id': target,
      if (nickname != null) 'nickname': nickname.trim(),
      'expected_revision': state.revision
    };
    try {
      final encoded = jsonEncode(command);
      if (_pendingCommand != encoded) {
        _pendingCommand = encoded;
        _pendingOperation = const Uuid().v4();
      }
      if (!active) return false;
      ConnectionPreferences accepted;
      if (changeRemote != null) {
        final response = await changeRemote!(_pendingOperation!, command);
        if (!active) return false;
        accepted = ConnectionPreferences.fromMap(response);
      } else {
        // Explicit uninitialized repository mode used by local test fixtures.
        final names = Map<String, String>.from(state.nicknames),
            archived = Set<String>.from(state.archived);
        if (action == 'nickname') {
          if (nickname!.trim().isEmpty) {
            names.remove(target);
          } else {
            names[target] = nickname.trim();
          }
        }
        if (action == 'archive') archived.add(target);
        if (action == 'restore') archived.remove(target);
        accepted = ConnectionPreferences(
            revision: state.revision + 1,
            nicknames: Map.unmodifiable(names),
            archived: Set.unmodifiable(archived),
            loaded: true);
      }
      // Cache failure does not undo an acknowledged server write. Revision
      // checks prevent an older delayed command overwriting a newer intent.
      _pendingCommand = null;
      _pendingOperation = null;
      state = accepted.withStatus(busy: true);
      try {
        await _stored(() async {
          await storage.write(key: key, value: jsonEncode(accepted.toMap()));
        });
      } catch (_) {
        if (changeRemote == null) {
          if (active) {
            state = before.withStatus(
                error:
                    'Connection change could not be saved on this device. Retry.');
          }
          return false;
        }
      }
      if (!active) return false;
      // Replaying an older response must not roll back newer device changes.
      if (readRemote != null) {
        try {
          final latest = ConnectionPreferences.fromMap(await readRemote!());
          if (!active) return false;
          state = latest.withStatus(busy: true);
          try {
            await _stored(() =>
                storage.write(key: key, value: jsonEncode(latest.toMap())));
          } catch (_) {}
          if (!active) return false;
          state = latest;
        } catch (_) {
          if (active) state = accepted;
        }
      } else {
        state = accepted;
      }
      return true;
    } on PostgrestException catch (error) {
      if (!active) return false;
      if (error.code == '40001') {
        _pendingCommand = null;
        _pendingOperation = null;
        if (!active) return false;
        state = state.withStatus(busy: false);
        await reload();
        if (active) {
          state = state.withStatus(
              error:
                  'Connections changed on another device. Review and save again.');
        }
      } else {
        state = state.withStatus(
            busy: false,
            error: 'Change could not be verified. Review and retry.');
      }
      return false;
    } catch (_) {
      if (active) {
        state = state.withStatus(
            busy: false,
            error:
                'Change could not be verified. Your current view is kept. Review and retry.');
      }
      return false;
    }
  }
}

final connectionPreferencesProvider =
    StateNotifierProvider<ConnectionPreferencesNotifier, ConnectionPreferences>(
        (ref) {
  final owner = ref.watch(currentUserProvider.select((user) => user.id));
  void changed() => ref.invalidateSelf();
  SupabaseConfig.sessionRevision.addListener(changed);
  ref.onDispose(() => SupabaseConfig.sessionRevision.removeListener(changed));
  final stamp = SupabaseConfig.captureSession();
  final connected = SupabaseConfig.isInitialized;
  return ConnectionPreferencesNotifier(
      owner: owner,
      current: () => SupabaseConfig.isCurrentSession(stamp),
      readRemote: connected
          ? () async => Map<String, dynamic>.from(await SupabaseConfig.client
              .rpc('connection_preferences_v1') as Map)
          : null,
      changeRemote: connected
          ? (operation, command) async => Map<String, dynamic>.from(
                  await SupabaseConfig.client.rpc('change_connection_v1',
                      params: {
                    'p_operation_id': operation,
                    'p_command': command
                  }) as Map)
          : null);
});
