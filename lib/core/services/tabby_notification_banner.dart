import '../theme/tabby_palette.dart';
import '../../shared/widgets/tabby_feedback.dart';

import 'package:flutter/material.dart';

import '../router/app_router.dart';
import '../theme/tabby_colors.dart';

/// Service for presenting floating in-app notification banners when real-time
/// events (new tabs, new expenses, payments, friend requests) occur.
class TabbyNotificationBanner {
  TabbyNotificationBanner._();

  static void show({
    required String title,
    required String body,
    String? tabId,
    IconData icon = Icons.notifications_active_rounded,
  }) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final context = messenger.context;
    final feedback = TabbyFeedback.current(messenger);

    feedback.hideCurrentSnackBar();
    feedback.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        duration: const Duration(seconds: 4),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: TabbyPalette.of(context).surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TabbyColors.brandAmber, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: TabbyPalette.of(context).soft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: TabbyPalette.of(context).link,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TabbyPalette.of(context).text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 11,
                        color: TabbyPalette.of(context).secondaryText,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (tabId != null && tabId.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    feedback.hideCurrentSnackBar();
                    appRouter.push('/tabs/$tabId');
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: TabbyPalette.of(context).link,
                  ),
                  child: const Text(
                    'View',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
