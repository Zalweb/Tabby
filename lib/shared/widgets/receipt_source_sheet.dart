import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/tabby_colors.dart';

/// Modal bottom sheet letting the user choose where to get a receipt photo
/// from (camera or gallery). Resolves to the chosen [ImageSource], or null
/// when dismissed.
class ReceiptSourceSheet extends StatelessWidget {
  const ReceiptSourceSheet({super.key});

  /// Shows the sheet and resolves to the chosen [ImageSource], or null when
  /// the user dismisses it.
  static Future<ImageSource?> show(BuildContext context) {
    return showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const ReceiptSourceSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TabbyColors.surfaceWhite,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Receipt Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose where to get the receipt image.',
                style: TextStyle(
                  fontSize: 12,
                  color: TabbyColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _sourceIcon(Icons.photo_camera_rounded),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TabbyColors.brandDarkTeal,
                  ),
                ),
                subtitle: const Text(
                  'Capture the receipt with the camera',
                  style:
                      TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _sourceIcon(Icons.photo_library_rounded),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TabbyColors.brandDarkTeal,
                  ),
                ),
                subtitle: const Text(
                  'Pick an existing receipt image',
                  style:
                      TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
                ),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sourceIcon(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: TabbyColors.brandMintAccent,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: TabbyColors.brandEmerald),
    );
  }
}
