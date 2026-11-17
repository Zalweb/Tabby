import 'tabby_feedback.dart';
import '../../core/theme/motion_preferences.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/tabby_palette.dart';

/// Modal bottom sheet letting the user choose where to get a receipt photo
/// from (camera or gallery). Resolves to the chosen [ImageSource], or null
/// when dismissed.
class ReceiptSourceSheet extends StatelessWidget {
  const ReceiptSourceSheet({super.key});

  /// Shows the sheet and resolves to the chosen [ImageSource], or null when
  /// the user dismisses it.
  static Future<ImageSource?> show(BuildContext context) {
    return showTabbyBottomSheet<ImageSource?>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const ReceiptSourceSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TabbyPalette.of(context).surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Receipt Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TabbyPalette.of(context).text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose where to get the receipt image.',
                style: TextStyle(
                  fontSize: 12,
                  color: TabbyPalette.of(context).secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _sourceIcon(context, Icons.photo_camera_rounded),
                title: Text(
                  'Take Photo',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TabbyPalette.of(context).text,
                  ),
                ),
                subtitle: Text(
                  'Capture the receipt with the camera',
                  style: TextStyle(
                    fontSize: 12,
                    color: TabbyPalette.of(context).secondaryText,
                  ),
                ),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _sourceIcon(context, Icons.photo_library_rounded),
                title: Text(
                  'Choose from Gallery',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TabbyPalette.of(context).text,
                  ),
                ),
                subtitle: Text(
                  'Pick an existing receipt image',
                  style: TextStyle(
                    fontSize: 12,
                    color: TabbyPalette.of(context).secondaryText,
                  ),
                ),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _sourceIcon(BuildContext context, IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).soft,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: TabbyPalette.of(context).link),
    );
  }
}
