import 'package:flutter/foundation.dart';

@immutable
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.ownerUserId,
    required this.provider,
    required this.displayName,
    required this.accountLabel,
    this.qrStoragePath,
    this.qrUrl,
    this.isActive = true,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerUserId;
  final String provider;
  final String displayName;
  final String accountLabel;
  final String? qrStoragePath;
  final String? qrUrl;
  final bool isActive;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    return PaymentMethod(
      id: _string(map['id']),
      ownerUserId: _string(map['owner_user_id'] ?? map['ownerUserId']),
      provider: _string(map['provider']),
      displayName: _string(map['display_name'] ?? map['displayName']),
      accountLabel: _string(map['account_label'] ?? map['accountLabel']),
      qrStoragePath:
          _nullableString(map['qr_storage_path'] ?? map['qrStoragePath']),
      qrUrl: _nullableString(map['qr_url'] ?? map['qrUrl']),
      isActive: _bool(map['is_active'] ?? map['isActive'], fallback: true),
      isDefault: _bool(map['is_default'] ?? map['isDefault']),
      createdAt: _date(map['created_at'] ?? map['createdAt']),
      updatedAt: _date(map['updated_at'] ?? map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner_user_id': ownerUserId,
        'provider': provider,
        'display_name': displayName,
        'account_label': accountLabel,
        'qr_storage_path': qrStoragePath,
        'qr_url': qrUrl,
        'is_active': isActive,
        'is_default': isDefault,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  PaymentMethod copyWith({
    String? id,
    String? ownerUserId,
    String? provider,
    String? displayName,
    String? accountLabel,
    String? qrStoragePath,
    String? qrUrl,
    bool? isActive,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      provider: provider ?? this.provider,
      displayName: displayName ?? this.displayName,
      accountLabel: accountLabel ?? this.accountLabel,
      qrStoragePath: qrStoragePath ?? this.qrStoragePath,
      qrUrl: qrUrl ?? this.qrUrl,
      isActive: isActive ?? this.isActive,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<PaymentMethod> fromLegacyUser(Map<String, dynamic> user) {
    final gcash = _nullableString(user['gcash_number'] ?? user['gcashNumber']);
    final maya = _nullableString(user['maya_number'] ?? user['mayaNumber']);
    final qrUrl = _nullableString(user['qr_code_url'] ?? user['qrCodeUrl']);
    final ownerId = _string(user['id']);

    if (gcash == null && maya == null && qrUrl == null) return const [];

    final methods = <PaymentMethod>[];
    if (gcash != null) {
      methods.add(PaymentMethod(
        id: 'legacy-$ownerId-gcash',
        ownerUserId: ownerId,
        provider: 'gcash',
        displayName: 'GCash',
        accountLabel: gcash,
        qrUrl: qrUrl,
        isDefault: true,
      ));
    }
    if (maya != null) {
      methods.add(PaymentMethod(
        id: 'legacy-$ownerId-maya',
        ownerUserId: ownerId,
        provider: 'maya',
        displayName: 'Maya',
        accountLabel: maya,
        qrUrl: qrUrl,
        isDefault: gcash == null,
      ));
    }
    if (methods.isEmpty && qrUrl != null) {
      methods.add(PaymentMethod(
        id: 'legacy-$ownerId-qr',
        ownerUserId: ownerId,
        provider: 'other',
        displayName: 'Payment QR',
        accountLabel: '',
        qrUrl: qrUrl,
        isDefault: true,
      ));
    }
    return methods;
  }

  static List<PaymentMethod> defaultFirst(Iterable<PaymentMethod> methods) {
    final ordered = methods.where((method) => method.isActive).toList();
    ordered.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    });
    return ordered;
  }

  static String _string(dynamic value) => value is String ? value : '';

  static String? _nullableString(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value;
  }

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  static DateTime? _date(dynamic value) {
    if (value is DateTime) return value;
    return value is String ? DateTime.tryParse(value) : null;
  }

  @override
  bool operator ==(Object other) {
    return other is PaymentMethod &&
        id == other.id &&
        ownerUserId == other.ownerUserId &&
        provider == other.provider &&
        displayName == other.displayName &&
        accountLabel == other.accountLabel &&
        qrStoragePath == other.qrStoragePath &&
        qrUrl == other.qrUrl &&
        isActive == other.isActive &&
        isDefault == other.isDefault &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        ownerUserId,
        provider,
        displayName,
        accountLabel,
        qrStoragePath,
        qrUrl,
        isActive,
        isDefault,
        createdAt,
        updatedAt,
      );
}

@immutable
class PaymentMethodDraft {
  const PaymentMethodDraft({
    required this.provider,
    required this.displayName,
    required this.accountLabel,
    this.qrBytes,
    this.qrExtension,
    this.qrMimeType,
  });

  final String provider;
  final String displayName;
  final String accountLabel;
  final Uint8List? qrBytes;
  final String? qrExtension;
  final String? qrMimeType;

  bool get hasQr => qrBytes != null && qrBytes!.isNotEmpty;

  bool get isValid =>
      provider.trim().isNotEmpty && displayName.trim().isNotEmpty;
}
