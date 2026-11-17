import '../../../shared/widgets/tabby_feedback.dart';
import 'privacy_controls_screen.dart';
import '../../../core/theme/motion_preferences.dart';
import 'profile_avatar.dart';
import 'profile_avatar_sheet.dart';
import 'profile_edit_sheet.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/background_reminder_service.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../core/widgets/app_version_footer.dart';
import '../../../shared/widgets/notification_center_sheet.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../../tabs/domain/models.dart';
import '../../payment_methods/application/payment_methods_provider.dart';
import '../../payment_methods/presentation/payment_methods_sheet.dart';
import '../../app_update/data/app_update_service.dart';
import '../../app_update/domain/app_update_models.dart';
import '../application/sync_diagnostics_provider.dart';
import 'sync_diagnostics_sheet.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef FriendLookup = Future<TabbyUser?> Function(String friendCode);
typedef FriendRequestSubmitter = Future<FriendRequest?> Function(
  String friendCode,
);

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(userSettingsProvider);
    final settingsNotifier = ref.read(userSettingsProvider.notifier);
    final paymentMethods = ref.watch(paymentMethodsProvider(user.id));
    final syncDiagnostics = ref.watch(syncDiagnosticsProvider);
    final pendingRequestsCount = ref
        .watch(tabbyProvider)
        .friendRequests
        .where((r) => r.isIncoming && r.status == FriendRequestStatus.pending)
        .length;

    void updateBiometrics(bool value) async {
      final enabled = await settingsNotifier.toggleBiometrics(value);
      if (!context.mounted) return;
      TabbyFeedback.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? (value
                        ? 'Biometric security enabled.'
                        : 'Biometric security disabled.')
                  : 'This device could not verify biometric security.',
            ),
          ),
        );
    }

    Future<void> updateNotifications(bool value) async {
      final saved = await settingsNotifier.toggleNotifications(value);
      if (!context.mounted) return;
      TabbyFeedback.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? (value
                        ? 'Notifications enabled.'
                        : 'Notifications disabled.')
                  : ref.read(userSettingsProvider).notificationError ??
                        'Notification settings could not be updated.',
            ),
          ),
        );
    }

    return Scaffold(
      backgroundColor: TabbyPalette.of(context).canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildProfileOuterHeader(context),
            Expanded(
              child: Material(
                color: TabbyPalette.of(context).canvas,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(36),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProfileIdentity(context, user),
                      const SizedBox(height: 22),
                      _buildSectionHeading('Account'),
                      const SizedBox(height: 8),
                      _buildSettingsCard(
                        rows: [
                          _buildSettingsRow(
                            icon: Icons.account_balance_wallet_outlined,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Payment Methods',
                            subtitle: paymentMethods.methods.isEmpty
                                ? 'Add a payment method'
                                : '${paymentMethods.methods.first.displayName} · ${paymentMethods.methods.length} saved',

                            onTap: () => PaymentMethodsSheet.show(
                              context,
                              ownerUserId: user.id,
                            ),
                          ),
                          _buildSettingsRow(
                            icon: Icons.security_outlined,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Security',
                            subtitle: settings.biometricsEnabled
                                ? 'Biometric security active'
                                : 'Biometric security disabled',
                            trailing: _buildSwitchWithDetails(
                              value: settings.biometricsEnabled,
                              tooltip: 'Security Settings',
                              onChanged: updateBiometrics,
                              onDetails: () =>
                                  _showSecuritySettingsSheet(context),
                            ),
                            onTap: () =>
                                updateBiometrics(!settings.biometricsEnabled),
                          ),
                          _buildSettingsRow(
                            icon: Icons.people_alt_outlined,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Manage Friends',
                            subtitle: pendingRequestsCount > 0
                                ? '$pendingRequestsCount pending request${pendingRequestsCount > 1 ? "s" : ""}'
                                : 'Friends and connections',
                            trailing: pendingRequestsCount > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: TabbyPalette.of(context).soft,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$pendingRequestsCount new',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: TabbyPalette.of(context).text,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () => context.push('/profile/connections'),
                          ),
                          _buildSettingsRow(
                            icon: Icons.person_add_alt_1_outlined,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Connect by Tabby ID',
                            subtitle: 'Add friend using their Tabby ID',
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: TabbyPalette.of(context).soft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_add_rounded,
                                    size: 14,
                                    color: TabbyPalette.of(context).link,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Connect',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyPalette.of(context).link,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () => _showConnectByIdSheet(context),
                          ),
                          _buildSettingsRow(
                            icon: Icons.groups_outlined,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Create a Group',
                            subtitle: 'Shared barkada or roommate tabs',
                            onTap: () => _showCreateGroupSheet(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildSectionHeading('Preferences'),
                      const SizedBox(height: 8),
                      _buildSettingsCard(
                        rows: [
                          _buildSettingsRow(
                            icon: Icons.notifications_none_rounded,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Notifications',
                            subtitle: 'Settings',
                            trailing: _buildSwitchWithDetails(
                              value: settings.notificationsEnabled,
                              tooltip: 'Notification Preferences',
                              onChanged: updateNotifications,
                              onDetails: () =>
                                  _showNotificationPreferencesSheet(context),
                            ),
                            onTap: () => updateNotifications(
                              !settings.notificationsEnabled,
                            ),
                          ),
                          _buildSettingsRow(
                            icon: Icons.palette_outlined,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Appearance',
                            subtitle:
                                '${settings.darkModeEnabled ? 'Dark' : 'Light'} mode · ${settings.motionEnabled ? 'Motion on' : 'Motion off'}',
                            onTap: () => _showAppearanceSheet(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildSectionHeading('Data & Support'),
                      const SizedBox(height: 8),
                      _buildSettingsCard(
                        rows: [
                          _buildSettingsRow(
                            icon: Icons.cloud_done_outlined,
                            iconBackground: TabbyPalette.of(context).accentTint,
                            iconColor: TabbyColors.accentBurnt,
                            title: 'Sync & Offline',
                            subtitle: 'Offline cache and server status',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TabbyPalette.of(context).soft,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    syncStatusLabel(syncDiagnostics),
                                    style: TextStyle(
                                      color:
                                          syncDiagnostics.status ==
                                              SyncStatus.offline
                                          ? TabbyPalette.of(context).errorText
                                          : TabbyPalette.of(context).link,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: TabbyPalette.of(context).secondaryText,
                                ),
                              ],
                            ),
                            onTap: () => SyncDiagnosticsSheet.show(context),
                          ),
                          _buildSettingsRow(
                            icon: Icons.privacy_tip_outlined,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Privacy & Your Data',
                            subtitle: 'Visibility and a profile copy',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PrivacyControlsScreen(),
                              ),
                            ),
                          ),
                          _buildSettingsRow(
                            icon: Icons.headset_mic_outlined,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'Help Center',
                            subtitle: 'Customer support and FAQ',
                            onTap: () => _showHelpCenterSheet(context),
                          ),
                          _buildSettingsRow(
                            icon: Icons.info_outline_rounded,
                            iconBackground: TabbyPalette.of(context).soft,
                            iconColor: TabbyPalette.of(context).link,
                            title: 'About Tabby',
                            subtitle: 'Version and app information',
                            onTap: () => _showAboutTabbySheet(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showLogoutConfirmation(context),
                          icon: const Icon(Icons.logout_rounded, size: 17),
                          label: const Text('Log Out'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TabbyPalette.of(context).errorText,
                            side: const BorderSide(
                              color: TabbyColors.alertRed,
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Tabby Phase 1 MVP',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: TabbyPalette.of(context).secondaryText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const AppVersionFooter(),
                            const SizedBox(height: 2),
                            Text(
                              'Keep tabs. Settle up.',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: TabbyPalette.of(context).secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOuterHeader(BuildContext context) {
    return Container(
      color: TabbyPalette.of(context).canvas,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Profile & Settings',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: TabbyPalette.of(context).text,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: TabbyPalette.of(context).surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Badge(
                isLabelVisible:
                    ref.watch(tabbyProvider).unreadNotificationCount > 0,
                backgroundColor: TabbyColors.alertRed,
                label: Text(
                  ref.watch(tabbyProvider).unreadNotificationCount > 9
                      ? '9+'
                      : '${ref.watch(tabbyProvider).unreadNotificationCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: TabbyColors.surfaceWhite,
                  ),
                ),
                child: Icon(
                  ref.watch(tabbyProvider).unreadNotificationCount > 0
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  size: 22,
                  color: TabbyPalette.of(context).text,
                ),
              ),
              onPressed: () => NotificationCenterSheet.show(context),
              tooltip: 'Notifications',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileIdentity(BuildContext context, TabbyUser user) {
    final avatar = GestureDetector(
      onTap: () => _showAvatarOptionsSheet(context, user),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: TabbyColors.brandAmber, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: ColoredBox(
                color: TabbyColors.brandAmber,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: TabbyColors.brandInk),
                  child: IconTheme(
                    data: const IconThemeData(color: TabbyColors.brandInk),
                    child: ProfileAvatar(
                      key: ValueKey(user.id),
                      reference: user.avatarUrl,
                      name: user.displayName,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: TabbyColors.brandInk,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 12,
                color: TabbyColors.surfaceWhite,
              ),
            ),
          ),
        ],
      ),
    );
    final details = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: TabbyPalette.of(context).text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Your Tabby ID',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: TabbyPalette.of(context).secondaryText,
            ),
          ),
          Row(
            children: [
              Flexible(
                child: Text(
                  user.friendCode ?? 'Not available yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: TabbyPalette.of(context).link,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 15),
                color: TabbyPalette.of(context).secondaryText,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                tooltip: 'Copy Tabby ID',
                onPressed: user.friendCode == null
                    ? null
                    : () {
                        Clipboard.setData(
                          ClipboardData(text: user.friendCode!),
                        );
                        TabbyFeedback.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Tabby ID copied to clipboard.'),
                            ),
                          );
                      },
              ),
            ],
          ),
        ],
      ),
    );
    final edit = OutlinedButton.icon(
      onPressed: () => _showEditProfileSheet(context, user),
      icon: const Icon(Icons.edit_outlined, size: 14),
      label: const Text('Edit Profile'),
      style: OutlinedButton.styleFrom(
        foregroundColor: TabbyPalette.of(context).link,
        side: BorderSide(color: TabbyPalette.of(context).controlBorder),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final compact =
            c.maxWidth < 330 || MediaQuery.textScalerOf(context).scale(16) > 22;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [avatar, const SizedBox(width: 12), details]),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: edit),
            ],
          );
        }
        return Row(
          children: [
            avatar,
            const SizedBox(width: 10),
            details,
            const SizedBox(width: 6),
            edit,
          ],
        );
      },
    );
  }

  Widget _buildSectionHeading(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: TabbyPalette.of(context).text,
        letterSpacing: 0.1,
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> rows}) {
    final children = <Widget>[];
    for (var index = 0; index < rows.length; index++) {
      if (index > 0) children.add(const Divider(height: 1));
      children.add(rows[index]);
    }

    return Material(
      color: TabbyPalette.of(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: TabbyPalette.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconBackground,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      minVerticalPadding: 0,
      horizontalTitleGap: 12,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconBackground,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: iconColor, size: 19),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: TabbyPalette.of(context).text,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: TabbyPalette.of(context).secondaryText,
        ),
      ),
      trailing:
          trailing ??
          Icon(
            Icons.chevron_right_rounded,
            color: TabbyPalette.of(context).secondaryText,
            size: 20,
          ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchWithDetails({
    required bool value,
    required String tooltip,
    required ValueChanged<bool> onChanged,
    required VoidCallback onDetails,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: onChanged),
        IconButton(
          tooltip: tooltip,
          onPressed: onDetails,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: Icon(
            Icons.chevron_right_rounded,
            color: TabbyPalette.of(context).secondaryText,
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget _buildPreferenceChoice({
    required String title,
    required bool selected,
    required VoidCallback? onTap,
    String? subtitle,
  }) {
    final p = TabbyPalette.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: selected ? p.link : p.border,
        width: selected ? 1.5 : 1,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? p.soft : p.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          selected: selected,
          enabled: onTap != null,
          shape: shape,
          selectedTileColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            color: selected
                ? TabbyPalette.of(context).link
                : TabbyPalette.of(context).secondaryText,
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  void _showAboutTabbySheet(BuildContext context) {
    showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) {
          final checker = AppUpdateService();
          return Material(
            color: TabbyPalette.of(context).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: FutureBuilder<AppUpdateCheckResult>(
                  future: checker.checkStatus(),
                  builder: (context, snapshot) {
                    final result = snapshot.data;
                    final statusText = result == null
                        ? 'Checking for updates...'
                        : switch (result.status) {
                            AppUpdateStatus.upToDate => 'Tabby is up to date.',
                            AppUpdateStatus.updateAvailable =>
                              'A new update is available.',
                            AppUpdateStatus.unavailable =>
                              'Update check unavailable. Try again later.',
                            AppUpdateStatus.checking =>
                              'Checking for updates...',
                          };
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'About Tabby',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: TabbyPalette.of(context).text,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, pkgSnapshot) {
                            final pkg = pkgSnapshot.data;
                            final displayVer = pkg != null
                                ? (pkg.buildNumber.isEmpty
                                      ? pkg.version
                                      : '${pkg.version}+${pkg.buildNumber}')
                                : '1.0.3+4';
                            return Text(
                              'Version $displayVer',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 13,
                            color: TabbyPalette.of(context).secondaryText,
                          ),
                        ),
                        if (result?.update != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Version ${result!.update!.release.version.fullDisplayValue} is ready.',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(result.update!.release.releaseNotes),
                        ],
                        const SizedBox(height: 20),
                        if (result?.status ==
                            AppUpdateStatus.updateAvailable) ...[
                          TabbyButton(
                            label: 'Update on Website',
                            onPressed: () async {
                              final url = Uri.parse(
                                'https://tabby-web-fawn.vercel.app/#download',
                              );
                              try {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {}
                            },
                          ),
                          const SizedBox(height: 10),
                        ] else ...[
                          TabbyButton(
                            label:
                                snapshot.connectionState ==
                                    ConnectionState.waiting
                                ? 'Checking...'
                                : 'Check for Updates',
                            onPressed:
                                snapshot.connectionState ==
                                    ConnectionState.waiting
                                ? null
                                : () => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Center(
                          child: TextButton.icon(
                            onPressed: () async {
                              final url = Uri.parse(
                                'https://tabby-web-fawn.vercel.app',
                              );
                              try {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {}
                            },
                            icon: Icon(
                              Icons.language_rounded,
                              size: 16,
                              color: TabbyPalette.of(context).text,
                            ),
                            label: Text(
                              'Visit Tabby Website',
                              style: TextStyle(
                                color: TabbyPalette.of(context).text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: TextButton(
                            onPressed: () async {
                              final url = Uri.parse('https://icons8.com');
                              try {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {}
                            },
                            child: Text(
                              'App icon by Icons8',
                              style: TextStyle(
                                fontSize: 12,
                                color: TabbyPalette.of(context).secondaryText,
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAppearanceSheet(BuildContext context) {
    showTabbyBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle.noAnimation,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(userSettingsProvider),
              notifier = ref.read(userSettingsProvider.notifier);
          return Material(
            color: TabbyPalette.of(context).surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Appearance',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: TabbyPalette.of(context).text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPreferenceChoice(
                      title: 'Light mode',
                      selected: !settings.darkModeEnabled,
                      onTap: settings.appearanceBusy
                          ? null
                          : () =>
                                notifier.setAppearancePreferences(dark: false),
                    ),
                    _buildPreferenceChoice(
                      title: 'Dark mode',
                      selected: settings.darkModeEnabled,
                      onTap: settings.appearanceBusy
                          ? null
                          : () => notifier.setAppearancePreferences(dark: true),
                    ),
                    SwitchListTile(
                      title: const Text('Motion effects'),
                      subtitle: const Text(
                        'System reduced motion always takes priority.',
                      ),
                      value: settings.motionEnabled,
                      onChanged: settings.appearanceBusy
                          ? null
                          : (value) => notifier.setAppearancePreferences(
                              motion: value,
                            ),
                    ),
                    if (settings.appearanceBusy)
                      const LinearProgressIndicator(),
                    if (settings.appearanceError != null)
                      Text(settings.appearanceError!),
                    TabbyButton(
                      label: 'Done',
                      onPressed: settings.appearanceBusy
                          ? null
                          : () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAvatarOptionsSheet(BuildContext context, TabbyUser user) {
    showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileAvatarSheet(user: user),
    );
  }

  // 2. Edit Profile Modal Sheet
  void _showEditProfileSheet(BuildContext context, TabbyUser user) {
    showTabbyFormPage<void>(
      context: context,
      builder: (_) => ProfileEditSheet(user: user),
    );
  }

  // 3b. Security & App Lock Sheet
  void _showSecuritySettingsSheet(BuildContext context) {
    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final settings = ref.watch(userSettingsProvider);
            final notifier = ref.read(userSettingsProvider.notifier);
            return Material(
              color: TabbyPalette.of(context).surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Security & App Lock',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyPalette.of(context).text,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Biometric Unlock',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        subtitle: FutureBuilder<String>(
                          future: notifier.biometricLabel(),
                          builder: (context, snapshot) => Text(
                            settings.biometricsEnabled
                                ? '${snapshot.data ?? 'Biometric'} active'
                                : (snapshot.data ?? 'Checking device support'),
                            style: TextStyle(
                              fontSize: 12,
                              color: TabbyPalette.of(context).secondaryText,
                            ),
                          ),
                        ),
                        value: settings.biometricsEnabled,
                        onChanged: (val) async {
                          await notifier.toggleBiometrics(val);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Passcode Protection',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        subtitle: Text(
                          'Require a security PIN to access ledgers',
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyPalette.of(context).secondaryText,
                          ),
                        ),
                        value: settings.passcodeEnabled,
                        onChanged: (val) async {
                          if (val) {
                            _showPinSetupSheet(context);
                          } else {
                            final cleared = await notifier.clearPin();
                            if (!cleared && context.mounted) {
                              TabbyFeedback.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Device authentication is required to remove your PIN.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                      if (settings.passcodeEnabled)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _showPinSetupSheet(context),
                            icon: const Icon(Icons.pin_outlined, size: 17),
                            label: const Text('Change PIN'),
                          ),
                        ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Auto-Lock on Exit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        subtitle: Text(
                          'Lock Tabby immediately when backgrounded',
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyPalette.of(context).secondaryText,
                          ),
                        ),
                        value: settings.autoLockEnabled,
                        onChanged: (val) {
                          notifier.update(autoLockEnabled: val);
                        },
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: TabbyPalette.of(context).soft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: TabbyPalette.of(context).link,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Financial records are stored locally with AES-256 device encryption and synced via TLS 1.3 to Supabase with Row Level Security.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: TabbyPalette.of(context).text,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TabbyButton(
                        label: 'Done',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPinSetupSheet(BuildContext context) {
    showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinSetupSheet(hostContext: context),
    );
  }

  // 3c. Notification Preferences Sheet
  void _showNotificationPreferencesSheet(BuildContext context) {
    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final settings = ref.watch(userSettingsProvider);
            final notifier = ref.read(userSettingsProvider.notifier);
            return Material(
              color: TabbyPalette.of(context).surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Notification Preferences',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyPalette.of(context).text,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Device notifications',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        subtitle: Text(
                          'Master switch for all device notifications',
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyPalette.of(context).secondaryText,
                          ),
                        ),
                        value: settings.notificationsEnabled,
                        onChanged: (val) {
                          notifier.toggleNotifications(val);
                        },
                      ),
                      if (settings.notificationError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            settings.notificationError!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      if (settings.notificationsEnabled &&
                          settings.reminderNudgesEnabled)
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              BackgroundReminderService.instance.readyNotifier,
                          builder: (context, ready, child) => ready
                              ? const SizedBox.shrink()
                              : const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'Background reminders are unavailable. You can still review reminders in Tabby.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                        ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Instant Payment Alerts',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        subtitle: Text(
                          'Notify when friends record or confirm a payment',
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyPalette.of(context).secondaryText,
                          ),
                        ),
                        value: settings.paymentAlertsEnabled,
                        onChanged: settings.notificationsEnabled
                            ? (val) {
                                notifier.setNotificationPreferences(
                                  payments: val,
                                );
                              }
                            : null,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Gentle Reminder Nudges',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        subtitle: Text(
                          'Notify when due dates approach or tabs remain open',
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyPalette.of(context).secondaryText,
                          ),
                        ),
                        value: settings.reminderNudgesEnabled,
                        onChanged: settings.notificationsEnabled
                            ? (val) {
                                notifier.setNotificationPreferences(
                                  reminders: val,
                                );
                              }
                            : null,
                      ),
                      const SizedBox(height: 24),
                      TabbyButton(
                        label: 'Done',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 4. Currency Precision Info Sheet

  void _showHelpCenterSheet(BuildContext context) {
    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Material(
          color: TabbyPalette.of(context).surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Help Center & FAQ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyPalette.of(context).text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      _buildFaqItem(
                        question: 'What is a Tab in Tabby?',
                        answer: 'A Tab is the complete running bilateral financial ledger between two people. Regardless of how many meals, rides, or bills you share, there is only one running balance between you.',
                        initiallyExpanded: true,
                      ),
                      _buildFaqItem(
                        question: 'How does Bill Splitting work?',
                        answer: 'You can choose a 50/50 Split for equal halves or Full Share if one person covered the whole item. Centavo-accurate rounding ensures exact balances.',
                      ),
                      _buildFaqItem(
                        question: 'How do I settle up?',
                        answer: 'You can pay using GCash, Maya, Cash, or Bank Transfer. Once payment is recorded in the tab, Tabby updates your net balance immediately.',
                      ),
                      _buildFaqItem(
                        question: 'What is a Friendly Reminder?',
                        answer: 'Instead of awkward texts, Tabby provides a cute mascot reminder card that you can share with your friend to defuse any tension.',
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: TabbyPalette.of(context).soft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Still have questions?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: TabbyPalette.of(context).text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Our support team is always happy to assist you.',
                              style: TextStyle(
                                fontSize: 11,
                                color: TabbyPalette.of(context).secondaryText,
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                  const ClipboardData(text: 'support@tabby.ph'),
                                );
                                TabbyFeedback.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Support email copied to clipboard: support@tabby.ph',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy support@tabby.ph'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: TabbyPalette.of(context).text,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TabbyButton(
                  label: 'Close',
                  variant: TabbyButtonVariant.outline,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 7. Connect by Tabby ID Modal Sheet
  void _showConnectByIdSheet(BuildContext context) {
    showTabbyBottomSheet(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ConnectByIdSheet(
        findFriend: (code) =>
            ref.read(tabbyProvider.notifier).findFriendByCode(code),
        sendFriendRequest: (code) =>
            ref.read(tabbyProvider.notifier).sendFriendRequestByCode(code),
      ),
    );
  }

  // 7e. Create Group Sheet
  void _showCreateGroupSheet(BuildContext context) {
    TabbyFeedback.of(context).clearSnackBars();
    final nameController = TextEditingController();
    final friends = ref.read(friendsProvider);
    final selectedFriendIds = <String>{};
    bool isSubmitting = false;

    showTabbyFormPage(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Material(
                color: TabbyPalette.of(context).surface,
                borderRadius: BorderRadius.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: TabbyFormBody(
                    header: TabbyFormHeader(
                      title: 'Create New Group Tab',
                      onBack: isSubmitting
                          ? null
                          : () => Navigator.maybePop(sheetContext),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Keep tabs for barkada meals, roommates, or shared road trips.',
                          style: TextStyle(
                            fontSize: 12,
                            color: TabbyPalette.of(context).secondaryText,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          label: 'Group Name (e.g. Barkada Dinner, Room 302)',
                          controller: nameController,
                          icon: Icons.groups_rounded,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Select Members from Friends',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (friends.isEmpty)
                          Text(
                            'No accepted friends yet. Connect with a friend first.',
                            style: TextStyle(
                              fontSize: 12,
                              color: TabbyPalette.of(context).secondaryText,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: friends.map((friend) {
                              final isSelected = selectedFriendIds.contains(
                                friend.id,
                              );
                              return FilterChip(
                                label: Text(friend.displayName),
                                selected: isSelected,
                                selectedColor: TabbyPalette.of(context).soft,
                                checkmarkColor: TabbyPalette.of(context).link,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? TabbyPalette.of(context).link
                                      : TabbyPalette.of(context).text,
                                ),
                                onSelected: (val) {
                                  setModalState(() {
                                    if (val) {
                                      selectedFriendIds.add(friend.id);
                                    } else {
                                      selectedFriendIds.remove(friend.id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 24),
                        TabbyButton(
                          label: isSubmitting
                              ? 'Creating...'
                              : 'Create Group Tab',
                          isLoading: isSubmitting,
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  final groupName = nameController.text.trim();
                                  if (groupName.isEmpty) {
                                    TabbyFeedback.of(context).clearSnackBars();
                                    TabbyFeedback.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please enter a group name.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  if (selectedFriendIds.isEmpty) {
                                    TabbyFeedback.of(context).clearSnackBars();
                                    TabbyFeedback.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Select at least one accepted friend.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSubmitting = true);

                                  final memberNames = <String>[];
                                  for (final id in selectedFriendIds) {
                                    final f = friends
                                        .where((x) => x.id == id)
                                        .firstOrNull;
                                    if (f != null) {
                                      memberNames.add(f.displayName);
                                    }
                                  }

                                  ref
                                      .read(tabbyProvider.notifier)
                                      .addGroupTab(
                                        groupName: groupName,
                                        memberNames: memberNames,
                                        memberUserIds: selectedFriendIds
                                            .toList(),
                                      );

                                  Navigator.pop(sheetContext);
                                  TabbyFeedback.of(context).clearSnackBars();
                                  TabbyFeedback.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Group "$groupName" created successfully!',
                                      ),
                                    ),
                                  );
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 8. Logout Confirmation Dialog
  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      animationStyle: TabbyMotion.style(context),
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.logout_rounded,
                color: TabbyPalette.of(context).errorText,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'Log Out',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to log out of your Tabby account?',
            style: TextStyle(
              fontSize: 14,
              color: TabbyPalette.of(context).secondaryText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: TabbyPalette.of(context).secondaryText),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                // 1. Immediately invalidate auth flag — router redirects to /login
                final session = SupabaseConfig.captureSession();
                AppState.isAuthenticated.value = false;
                // 2. Clear in-memory providers
                ref.read(currentUserProvider.notifier).reset();
                ref.read(tabbyProvider.notifier).reset();
                // 3. Navigate immediately (no waiting for Supabase)
                if (context.mounted) context.go('/login');
                // 4. Clear local cache and sign out in background
                try {
                  await SupabaseTabbyRepository.instance.signOut(
                    expectedSession: session,
                  );
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TabbyColors.alertRed,
                foregroundColor: TabbyColors.surfaceWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Log Out'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: TabbyPalette.of(context).soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: TabbyPalette.of(context).text,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontSize: 12,
            color: TabbyPalette.of(context).secondaryText,
          ),
          prefixIcon: Icon(
            icon,
            size: 20,
            color: TabbyPalette.of(context).secondaryText,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildFaqItem({
    required String question,
    required String answer,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        title: Text(
          question,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: TabbyPalette.of(context).text,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              answer,
              style: TextStyle(
                fontSize: 12,
                color: TabbyPalette.of(context).secondaryText,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stateful owner for the Connect by Tabby ID sheet.
///
/// The lookup and request operations can outlive the modal route's reverse
/// animation. Keeping the controller and async state here means disposal is
/// handled by the widget lifecycle, while mounted checks prevent callbacks
/// from touching a sheet that has already been removed.
class ConnectByIdSheet extends StatefulWidget {
  const ConnectByIdSheet({
    super.key,
    required this.findFriend,
    required this.sendFriendRequest,
  });

  final FriendLookup findFriend;
  final FriendRequestSubmitter sendFriendRequest;

  @override
  State<ConnectByIdSheet> createState() => _ConnectByIdSheetState();
}

class _ConnectByIdSheetState extends State<ConnectByIdSheet> {
  late final TextEditingController _codeController;
  late final SessionStamp _session;
  String? _lookedUpCode;
  bool get _current => mounted && SupabaseConfig.isCurrentSession(_session);
  TabbyUser? _foundUser;
  String? _message;
  bool _isLookingUp = false;
  bool _isSending = false;
  bool _requestSent = false;
  int _lookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.captureSession();
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _lookupGeneration++;
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _findFriend() async {
    if (!_current || _isLookingUp || _isSending) return;

    final normalized = normalizeFriendCode(_codeController.text);
    if (normalized == null) {
      setState(() {
        _foundUser = null;
        _message = 'Enter a valid Tabby ID such as TAB-7K4P2M.';
      });
      return;
    }

    final lookupGeneration = ++_lookupGeneration;
    setState(() {
      _isLookingUp = true;
      _foundUser = null;
      _lookedUpCode = null;
      _message = null;
    });

    try {
      final user = await widget.findFriend(normalized);
      if (!_current || lookupGeneration != _lookupGeneration) return;
      setState(() {
        _isLookingUp = false;
        _foundUser = user;
        _lookedUpCode = user == null ? null : normalized;
        _message = user == null
            ? 'No Tabby account was found for that ID.'
            : null;
      });
    } catch (_) {
      if (!_current || lookupGeneration != _lookupGeneration) return;
      setState(() {
        _isLookingUp = false;
        _foundUser = null;
        _message = 'We could not look up that ID. Please try again.';
      });
    }
  }

  Future<void> _sendRequest() async {
    if (!_current || _isSending || _foundUser == null) return;

    final normalized = normalizeFriendCode(_codeController.text);
    if (normalized == null || normalized != _lookedUpCode) return;

    setState(() => _isSending = true);
    try {
      final request = await widget.sendFriendRequest(normalized);
      if (!_current) return;
      setState(() {
        _isSending = false;
        _requestSent = request != null;
        _message = request == null
            ? 'We could not send the request. Please try again.'
            : 'Request sent. They can accept it from their Profile.';
      });
    } catch (_) {
      if (!_current) return;
      setState(() {
        _isSending = false;
        _message = 'We could not send the request. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountDraftGuard(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Material(
          color: TabbyPalette.of(context).surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Connect with a Friend',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TabbyPalette.of(context).text,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the exact Tabby ID your friend shared with you.',
                    style: TextStyle(
                      fontSize: 12,
                      color: TabbyPalette.of(context).secondaryText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeController,
                    enabled: !_isSending,
                    onChanged: (_) {
                      ++_lookupGeneration;
                      setState(() {
                        _isLookingUp = false;
                        _foundUser = null;
                        _lookedUpCode = null;
                        _message = null;
                        _requestSent = false;
                      });
                    },
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Tabby ID',
                      hintText: 'TAB-7K4P2M',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      suffixIcon: IconButton(
                        tooltip: 'Find friend',
                        onPressed: _isLookingUp || _isSending
                            ? null
                            : _findFriend,
                        icon: _isLookingUp
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search_rounded),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onSubmitted: (_) => _findFriend(),
                  ),
                  if (_foundUser != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TabbyPalette.of(context).soft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: TabbyColors.brandAmber,
                            child: Text(
                              _foundUser!.displayName.isNotEmpty
                                  ? _foundUser!.displayName
                                        .substring(0, 1)
                                        .toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: TabbyPalette.of(context).text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _foundUser!.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: TabbyPalette.of(context).text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _requestSent
                            ? TabbyPalette.of(context).link
                            : TabbyPalette.of(context).errorText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_foundUser != null && !_requestSent)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSending ? null : _sendRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TabbyColors.brandAmber,
                          foregroundColor: TabbyColors.brandInk,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: TabbyColors.brandInk,
                                ),
                              )
                            : const Text('Send Friend Request'),
                      ),
                    )
                  else if (_requestSent)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinSetupSheet extends ConsumerStatefulWidget {
  const _PinSetupSheet({required this.hostContext});

  final BuildContext hostContext;

  @override
  ConsumerState<_PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends ConsumerState<_PinSetupSheet> {
  late final TextEditingController _pinController;
  late final TextEditingController _confirmController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _savePin() async {
    if (_pinController.text != _confirmController.text ||
        !RegExp(r'^\d{4,6}$').hasMatch(_pinController.text)) {
      TabbyFeedback.of(context).showSnackBar(
        const SnackBar(content: Text('Enter matching 4 to 6 digit PINs.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final saved = await ref
        .read(userSettingsProvider.notifier)
        .setPin(_pinController.text);
    if (!mounted) return;

    if (saved) {
      Navigator.of(context).pop();
      if (widget.hostContext.mounted) {
        TabbyFeedback.of(widget.hostContext).showSnackBar(
          const SnackBar(content: Text('PIN protection enabled.')),
        );
      }
    } else {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TabbyPalette.of(context).surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure PIN',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TabbyPalette.of(context).text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use a 4 to 6 digit PIN as a device fallback.',
                style: TextStyle(
                  fontSize: 12,
                  color: TabbyPalette.of(context).secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'New PIN',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 18),
              TabbyButton(
                label: _isSaving ? 'Saving...' : 'Save PIN',
                onPressed: _isSaving ? null : _savePin,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
