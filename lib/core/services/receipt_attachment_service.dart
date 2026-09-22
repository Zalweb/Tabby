import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Result of resolving a picked receipt image into a storable receipt URL.
class ReceiptResolution {
  const ReceiptResolution({
    required this.receiptUrl,
    required this.uploadedToCloud,
  });

  /// Supabase storage path when uploaded, otherwise the local file path.
  final String receiptUrl;

  /// True when the image was uploaded to the payment-proofs bucket.
  final bool uploadedToCloud;
}

/// Real receipt picking + upload pipeline for ledger entries and expenses.
///
/// Picks an image via `image_picker`, then uploads the bytes to the Supabase
/// `payment-proofs` bucket when an authenticated session is available. Falls
/// back to the local file path when offline, unauthenticated, or when the
/// upload fails, so offline logging keeps working (ADR-002).
class ReceiptAttachmentService {
  ReceiptAttachmentService._();

  static final ImagePicker _picker = ImagePicker();

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
  static Future<XFile?> pickImage(ImageSource source) {
    final override = debugPickImageOverride;
    if (override != null) return override(source);
    // Never launch a real platform picker inside widget tests.
    if (_isTestEnvironment) return Future.value(null);
    // imageQuality performs lightweight on-device compression before upload.
    return _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2048,
    );
  }

  /// Uploads [file] to the Supabase payment-proofs bucket when a session is
  /// available, reading its bytes for the upload. Falls back to the local file
  /// path when offline, unauthenticated, or when the upload fails, so offline
  /// logging keeps working. Read/IO errors propagate to the caller so they can
  /// be surfaced to the user.
  static Future<ReceiptResolution> resolveReceiptUrl({
    required XFile file,
    required String entryKey,
  }) async {
    final userId = SupabaseConfig.currentUserId;
    if (SupabaseConfig.isInitialized && userId != null) {
      final bytes = await file.readAsBytes();
      final extension = _extensionOf(file);
      final storagePath = '$userId/$entryKey.$extension';
      try {
        await SupabaseConfig.paymentProofsBucket.uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _mimeTypeFor(extension),
          ),
        );
        return ReceiptResolution(
          receiptUrl: storagePath,
          uploadedToCloud: true,
        );
      } catch (_) {
        // Fall through to the local path so offline logging still works.
      }
    }
    return ReceiptResolution(receiptUrl: file.path, uploadedToCloud: false);
  }

  static String _extensionOf(XFile file) {
    final ext = file.path.split('.').last.toLowerCase();
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'heic'};
    return allowed.contains(ext) ? ext : 'jpg';
  }

  static String _mimeTypeFor(String extension) =>
      extension == 'jpg' || extension == 'jpeg'
          ? 'image/jpeg'
          : 'image/$extension';
}
