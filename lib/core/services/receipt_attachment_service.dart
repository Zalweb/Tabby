import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../config/session_scope.dart';
import 'receipt_blob_store.dart';
import 'picker_recovery.dart';

/// Result of resolving a picked receipt image into a storable receipt URL.
class ReceiptResolution {
  const ReceiptResolution({
    required this.receiptUrl,
    required this.uploadedToCloud,
  });

  /// Stable private storage path or an account-scoped owned-byte reference.
  final String receiptUrl;

  /// True when the image was uploaded to the payment-proofs bucket.
  final bool uploadedToCloud;
}

/// Real receipt picking + upload pipeline for ledger entries and expenses.
///
/// Picks an image via `image_picker`, then uploads the bytes to the Supabase
/// `payment-proofs` bucket when an authenticated session is available. It
/// keeps owned encrypted bytes when offline or upload fails. Picker cache
/// files are not treated as durable references.
class ReceiptAttachmentService {
  ReceiptAttachmentService._();

  static final ImagePicker _picker = ImagePicker();
  static final recovery = PickerRecovery(
      pick: (source) {
        final override = debugPickImageOverride;
        if (override != null) return override(source);
        if (_isTestEnvironment) return Future.value(null);
        return _picker.pickImage(
            source: source, imageQuality: 85, maxWidth: 2048);
      },
      retrieve: () => !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              !_isTestEnvironment
          ? _picker.retrieveLostData()
          : Future.value(LostDataResponse.empty()));

  /// Test hook: when set, this is used instead of the platform image picker
  /// so widget tests never launch a real camera/gallery intent.
  static Future<XFile?> Function(ImageSource source)? debugPickImageOverride;

  static bool get _isTestEnvironment =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  /// True when a cloud upload will be attempted (Supabase session available).
  static bool get canUploadToCloud =>
      SupabaseConfig.isInitialized && SupabaseConfig.currentUserId != null;

  /// Picks an image from [source]. Returns null when the user cancels or when
  /// running inside a widget test without a [debugPickImageOverride].
  static Future<XFile?> pickImage(ImageSource source,
      {String purpose = 'attachment', String? ownerId}) {
    final owner = ownerId ?? SupabaseConfig.currentUserId ?? 'offline';
    final stamp = SupabaseConfig.captureSession();
    return recovery.select(
        owner: owner,
        purpose: purpose,
        source: source,
        isCurrent: () =>
            SupabaseConfig.isCurrentSession(stamp) &&
            (!SupabaseConfig.isInitialized ||
                SupabaseConfig.currentUserId == owner));
  }

  /// Uploads [file] to the Supabase payment-proofs bucket when a session is
  /// available, reading its bytes for the upload. Keeps account-scoped owned
  /// bytes when offline, unauthenticated, or when the upload fails, so offline
  /// logging keeps working. Read/IO errors propagate to the caller so they can
  /// be surfaced to the user.
  static Future<ReceiptResolution> resolveReceiptUrl({
    required XFile file,
    required String entryKey,
    String? ownerId,
  }) async {
    final session = SupabaseConfig.captureSession();
    final userId = SupabaseConfig.currentUserId;
    final bytes = await file.readAsBytes();
    if (!SupabaseConfig.isCurrentSession(session)) {
      throw StateError('Receipt account changed. Reopen the form.');
    }
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose a receipt image up to 5 MB.');
    }
    if (SupabaseConfig.isInitialized && userId != null) {
      final extension = _extensionOf(file);
      final storagePath = '$userId/$entryKey.$extension';
      try {
        await _uploadImmutableReceipt(
          storagePath,
          bytes,
          userId: userId,
          extension: extension,
          session: session,
        );
        return ReceiptResolution(
          receiptUrl: storagePath,
          uploadedToCloud: true,
        );
      } catch (_) {
        if (!SupabaseConfig.isCurrentSession(session)) rethrow;
        debugPrint(
          '[ReceiptAttachmentService] Cloud upload unavailable; keeping local receipt.',
        );
        // Preserve owned bytes so offline logging still works.
      }
    }
    final pending = await ReceiptBlobStore.save(
      bytes,
      ownerId: ownerId ?? userId ?? 'offline',
      extension: _extensionOf(file),
    );
    return ReceiptResolution(receiptUrl: pending, uploadedToCloud: false);
  }

  /// A committed money RPC can make this object immutable before its response
  /// reaches the queue. Retry by verifying owned bytes, never by overwriting.
  static Future<void> _uploadImmutableReceipt(
    String path,
    Uint8List bytes, {
    required String userId,
    required String extension,
    required SessionStamp session,
  }) async {
    void checkSession() {
      if (SupabaseConfig.currentUserId != userId ||
          !SupabaseConfig.isCurrentSession(session)) {
        throw StateError('Receipt account changed. Reopen the form.');
      }
    }

    checkSession();
    try {
      await SupabaseConfig.paymentProofsBucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          upsert: false,
          contentType: _mimeTypeFor(extension),
        ),
      );
    } on StorageException catch (error) {
      // Do not interpret authorization, network or provider errors as success.
      if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
      checkSession();
      final existing = await SupabaseConfig.paymentProofsBucket.download(path);
      checkSession();
      if (!listEquals(existing, bytes)) {
        throw StateError('Receipt upload identity has different saved bytes.');
      }
    }
    checkSession();
  }

  static bool _isCloudReceipt(String receiptUrl, String userId) {
    final uri = Uri.tryParse(receiptUrl);
    return receiptUrl.startsWith('$userId/') ||
        uri?.scheme == 'https' ||
        uri?.scheme == 'http';
  }

  static Future<String?> readPendingReceiptBytes(
    String? receiptUrl, {
    required String userId,
  }) async {
    if (receiptUrl != null && ReceiptBlobStore.isPending(receiptUrl)) {
      final bytes = await ReceiptBlobStore.read(receiptUrl, ownerId: userId);
      if (bytes == null) throw StateError('Pending receipt bytes unavailable.');
      return base64Encode(bytes);
    }
    if (receiptUrl == null ||
        receiptUrl.isEmpty ||
        _isCloudReceipt(receiptUrl, userId)) {
      return null;
    }
    final bytes = await XFile(receiptUrl).readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose a receipt image up to 5 MB.');
    }
    return base64Encode(bytes);
  }

  static Future<String?> uploadPendingReceipt(
    String? receiptUrl, {
    required String entryKey,
    required String userId,
    String? encodedBytes,
  }) async {
    final session = SupabaseConfig.captureSession();
    if (receiptUrl == null || receiptUrl.isEmpty) return receiptUrl;
    if (_isCloudReceipt(receiptUrl, userId)) return receiptUrl;
    if (SupabaseConfig.currentUserId != userId) {
      throw StateError('Receipt owner is not signed in');
    }
    final uploadBytes =
        encodedBytes ??
        await readPendingReceiptBytes(receiptUrl, userId: userId);
    if (uploadBytes != null) {
      final extension = _extensionOf(XFile(receiptUrl));
      final storagePath = '$userId/$entryKey.$extension';
      final bytes = base64Decode(uploadBytes);
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('Choose a receipt image up to 5 MB.');
      }
      await _uploadImmutableReceipt(
        storagePath,
        bytes,
        userId: userId,
        extension: extension,
        session: session,
      );
      return storagePath;
    }
    final resolution = await resolveReceiptUrl(
      file: XFile(receiptUrl),
      entryKey: entryKey,
    );
    if (!resolution.uploadedToCloud) {
      throw StateError('Receipt upload is still pending');
    }
    return resolution.receiptUrl;
  }

  static String _extensionOf(XFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'heic'};
    return allowed.contains(ext) ? ext : 'jpg';
  }

  static String _mimeTypeFor(String extension) =>
      extension == 'jpg' || extension == 'jpeg'
          ? 'image/jpeg'
          : 'image/$extension';
}
