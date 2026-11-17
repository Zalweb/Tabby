import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../payment_methods/domain/payment_method.dart';

class SetupPaymentItem {
  SetupPaymentItem(
      {required this.draft,
      this.isDefault = false,
      this.attempted = false,
      this.saved = false,
      this.error});
  PaymentMethodDraft draft;
  bool isDefault, attempted, saved;
  String? error;
  String get provider => draft.provider;
  String get displayName => draft.displayName;
  String get accountNumber => draft.accountLabel;
  Uint8List? get qrBytes => draft.qrBytes;
  bool get isAutoCropped => false;
  PaymentMethodDraft toDraft() => draft;
  Map<String, dynamic> toMap() => {
        'provider': provider,
        'name': displayName,
        'account': accountNumber,
        'method_id': draft.methodId,
        'operation_id': draft.operationId,
        'qr': qrBytes == null ? null : base64Encode(qrBytes!),
        'extension': draft.qrExtension,
        'mime': draft.qrMimeType,
        'preferred': isDefault,
        'attempted': attempted,
        'saved': saved,
        'error': error,
      };
  factory SetupPaymentItem.fromMap(Map<String, dynamic> map) =>
      SetupPaymentItem(
          draft: PaymentMethodDraft(
              provider: map['provider'] as String,
              displayName: map['name'] as String,
              accountLabel: map['account'] as String,
              methodId: map['method_id'] as String,
              operationId: map['operation_id'] as String,
              qrBytes: map['qr'] == null
                  ? null
                  : base64Decode(map['qr'] as String).asUnmodifiableView(),
              qrExtension: map['extension'] as String?,
              qrMimeType: map['mime'] as String?),
          isDefault: map['preferred'] == true,
          attempted: map['attempted'] == true,
          saved: map['saved'] == true,
          error: map['error'] as String?);
}

class ProfileSetupDraft extends ChangeNotifier {
  ProfileSetupDraft(this.owner, {this.storage = const FlutterSecureStorage()});
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static final _writes = <String, Future<void>>{};
  Future<void> _write(Future<void> Function() action) {
    final prior = _writes[owner];
    late final Future<void> guard;
    Future<void> run() async {
      try {
        await Future<void>.value();
        if (prior != null) await prior;
        await action();
      } finally {
        if (identical(_writes[owner], guard)) _writes.remove(owner);
      }
    }

    final result = run();
    guard = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _writes[owner] = guard;
    return result;
  }

  final String owner;
  final FlutterSecureStorage storage;
  final items = <SetupPaymentItem>[];
  String name = '', phone = '', avatar = 'asset:mascot';
  int step = 0;
  bool deferred = false, isSaving = false;
  bool get hasAttempts => items.any((item) => item.attempted);
  static String key(String actor) => 'tabby_${actor}_profile_setup_v1';
  Future<bool> restore() async {
    final pending = _writes[owner];
    if (pending != null) await pending;
    final raw = await storage.read(key: key(owner));
    if (raw == null) return false;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (map['owner'] != owner) {
      throw const FormatException('Setup account mismatch');
    }
    name = map['name'] as String;
    phone = map['phone'] as String;
    avatar = map['avatar'] as String;
    step = (map['step'] as num).toInt();
    deferred = map['deferred'] == true;
    items
      ..clear()
      ..addAll((map['items'] as List).map((row) =>
          SetupPaymentItem.fromMap(Map<String, dynamic>.from(row as Map))));
    _changed();
    return true;
  }

  static Future<bool> requiresCompletion(String actor) async {
    final pending = _writes[actor];
    if (pending != null) await pending;
    final raw = await const FlutterSecureStorage().read(key: key(actor));
    if (raw == null) return false;
    final map = jsonDecode(raw) as Map;
    if (map['owner'] != actor) {
      throw const FormatException('Setup account mismatch');
    }
    return map['deferred'] != true;
  }

  static Future<bool> hasRetainedMethods(String actor) async {
    final pending = _writes[actor];
    if (pending != null) await pending;
    final raw = await const FlutterSecureStorage().read(key: key(actor));
    if (raw == null) return false;
    final map = jsonDecode(raw) as Map;
    if (map['owner'] != actor) {
      throw const FormatException('Setup account mismatch');
    }
    return (map['items'] as List).any((item) => (item as Map)['saved'] != true);
  }

  Future<void> persist() async {
    final value = jsonEncode({
      'owner': owner,
      'name': name,
      'phone': phone,
      'avatar': avatar,
      'step': step,
      'deferred': deferred,
      'items': items.map((item) => item.toMap()).toList()
    });
    if (value.length > 20 * 1024 * 1024) {
      throw const FormatException('Choose smaller QR images for setup.');
    }
    await _write(() => storage.write(key: key(owner), value: value));
  }

  Future<void> add(PaymentMethodDraft draft) async {
    final item = SetupPaymentItem(
        draft: PaymentMethodDraft(
            provider: draft.provider,
            displayName: draft.displayName,
            accountLabel: draft.accountLabel,
            qrBytes: draft.qrBytes == null
                ? null
                : Uint8List.fromList(draft.qrBytes!).asUnmodifiableView(),
            qrExtension: draft.qrExtension,
            qrMimeType: draft.qrMimeType,
            methodId: draft.methodId ?? const Uuid().v4(),
            operationId: draft.operationId ?? const Uuid().v4()),
        isDefault: items.isEmpty);
    items.add(item);
    try {
      await persist();
    } catch (_) {
      items.remove(item);
      rethrow;
    }
    _changed();
  }

  Future<void> remove(int index) async {
    if (items[index].attempted || isSaving) {
      throw StateError(
          'Retry this method before managing it from your profile.');
    }
    final previous = List<SetupPaymentItem>.of(items);
    final drafts = {for (final row in items) row: row.draft};
    final preferences = {for (final row in items) row: row.isDefault};
    final removed = items.removeAt(index);
    if (removed.isDefault && items.isNotEmpty && !items.first.attempted) {
      final next = items.first;
      next.isDefault = true;
      final d = next.draft;
      next.draft = PaymentMethodDraft(
          provider: d.provider,
          displayName: d.displayName,
          accountLabel: d.accountLabel,
          qrBytes: d.qrBytes,
          qrExtension: d.qrExtension,
          qrMimeType: d.qrMimeType,
          methodId: d.methodId,
          operationId: const Uuid().v4());
    }
    try {
      await persist();
    } catch (_) {
      items
        ..clear()
        ..addAll(previous);
      for (final row in items) {
        row.draft = drafts[row]!;
        row.isDefault = preferences[row]!;
      }
      rethrow;
    }
    _changed();
  }

  Future<void> prefer(SetupPaymentItem item) async {
    if (hasAttempts || isSaving) {
      throw StateError('Preferences are frozen during retries.');
    }
    final previousDrafts = {for (final row in items) row: row.draft};
    final previousPreferences = {for (final row in items) row: row.isDefault};
    for (final row in items) {
      final selected = identical(item, row);
      if (row.isDefault == selected) continue;
      row.isDefault = selected;
      final draft = row.draft;
      row.draft = PaymentMethodDraft(
          provider: draft.provider,
          displayName: draft.displayName,
          accountLabel: draft.accountLabel,
          qrBytes: draft.qrBytes,
          qrExtension: draft.qrExtension,
          qrMimeType: draft.qrMimeType,
          methodId: draft.methodId,
          operationId: const Uuid().v4());
    }
    try {
      await persist();
    } catch (_) {
      for (final row in items) {
        row.draft = previousDrafts[row]!;
        row.isDefault = previousPreferences[row]!;
      }
      rethrow;
    }
    _changed();
  }

  Future<bool> saveMethods(
      Future<PaymentMethod?> Function(PaymentMethodDraft, bool) save,
      {required bool Function() current}) async {
    if (isSaving) return false;
    isSaving = true;
    deferred = false;
    try {
      await persist();
      if (!current()) return false;
      for (final item in items) {
        if (item.saved) continue;
        item.attempted = true;
        item.error = null;
        await persist();
        if (!current()) return false;
        _changed();
        try {
          final result = await save(item.toDraft(), item.isDefault);
          if (!current()) return false;
          if (result == null || result.id != item.draft.methodId) {
            item.error = 'Save not acknowledged. Retry keeps the same method.';
          } else {
            item.saved = true;
          }
        } catch (_) {
          if (!current()) return false;
          item.error = 'Could not verify the save. Retry this method.';
        }
        await persist();
        if (!current()) return false;
        _changed();
      }
      return items.every((item) => item.saved);
    } finally {
      isSaving = false;
      if (current()) _changed();
    }
  }

  Future<void> defer() async {
    final prior = deferred;
    deferred = true;
    try {
      await persist();
    } catch (_) {
      deferred = prior;
      rethrow;
    }
  }

  Future<void> clear() => _write(() => storage.delete(key: key(owner)));
}
