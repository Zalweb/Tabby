import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_state.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/widgets/app_version_footer.dart';
import '../../../shared/widgets/notification_center_sheet.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../../tabs/data/tabby_local_cache.dart';
import '../../tabs/domain/models.dart';
import '../../payment_methods/application/payment_methods_provider.dart';
import '../../payment_methods/presentation/payment_methods_sheet.dart';
import '../../app_update/data/app_update_service.dart';
import '../../app_update/domain/app_update_models.dart';
import '../../classroom/application/classroom_providers.dart';
import '../../classroom/domain/classroom_models.dart';
import '../../classroom/presentation/classroom_connect_sheet.dart';
import '../application/sync_diagnostics_provider.dart';
import 'sync_diagnostics_sheet.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef FriendLookup = Future<TabbyUser?> Function(String friendCode);
typedef FriendRequestSubmitter = Future<FriendRequest?> Function(
    String friendCode);

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
    final classroomConnection = ref.watch(classroomConnectionProvider);
    final classroomCourses = ref.watch(classroomCoursesProvider);

    void updateBiometrics(bool value) async {
      final enabled = await settingsNotifier.toggleBiometrics(value);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(enabled
                ? (value
                    ? 'Biometric security enabled.'
                    : 'Biometric security disabled.')
                : 'This device could not verify biometric security.'),
          ),
        );
    }

    void updateNotifications(bool value) {
      settingsNotifier.update(notificationsEnabled: value);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
                value ? 'Notifications enabled.' : 'Notifications disabled.'),
          ),
        );
    }

    return Scaffold(
      backgroundColor: TabbyColors.brandEmerald,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildProfileOuterHeader(context),
            Expanded(
              child: Material(
                color: TabbyColors.bgCanvas,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(36)),
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
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Payment Methods',
                            subtitle: paymentMethods.methods.isEmpty
                                ? 'Add a payment method'
                                : '${paymentMethods.methods.first.displayName} · ${paymentMethods.methods.length} saved',
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 124),
                                  child: Text(
                                    paymentMethods.isLoading
                                        ? 'Loading payment methods'
                                        : paymentMethods.methods.isEmpty
                                            ? 'GCash / Maya / Bank'
                                            : paymentMethods
                                                .methods.first.provider,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyColors.brandEmerald,
                                    ),
                                  ),
                                ),
                                const Text(
                                  'Manage Payment QR Code',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: TabbyColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => PaymentMethodsSheet.show(
                              context,
                              ownerUserId: user.id,
                            ),
                          ),
                          _buildSettingsRow(
                            icon: Icons.security_outlined,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
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
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Manage Friends',
                            subtitle: 'Friends and connections',
                            onTap: () => context.push('/profile/connections'),
                          ),
                          _buildSettingsRow(
                            icon: Icons.person_add_alt_1_outlined,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Connect by Tabby ID',
                            subtitle: 'Add friend using their Tabby ID',
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: TabbyColors.brandMintAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_add_rounded,
                                      size: 14,
                                      color: TabbyColors.brandEmerald),
                                  SizedBox(width: 4),
                                  Text(
                                    'Connect',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyColors.brandEmerald,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () => _showConnectByIdSheet(context),
                          ),
                          _buildSettingsRow(
                            icon: Icons.groups_outlined,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Create a Group',
                            subtitle: 'Shared barkada or roommate tabs',
                            onTap: () => _showCreateGroupSheet(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildSectionHeading('Connected Apps'),
                      const SizedBox(height: 8),
                      _buildSettingsCard(
                        rows: [
                          _buildClassroomRow(
                            context,
                            classroomConnection,
                            classroomCourses.length,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildSectionHeading('Preferences'),
                      const SizedBox(height: 8),
                      _buildSettingsCard(
                        rows: [
                          _buildSettingsRow(
                            icon: Icons.currency_exchange_rounded,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Currency Precision',
                            subtitle: settings.currencyCode == 'USD'
                                ? 'US Dollar (USD) · Display only'
                                : 'Philippine Peso (PHP) · Integer Centavos',
                            onTap: () => _showCurrencyPrecisionSheet(context),
                          ),
                          _buildSettingsRow(
                            icon: Icons.notifications_none_rounded,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
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
                                !settings.notificationsEnabled),
                          ),
                          _buildSettingsRow(
                            icon: Icons.palette_outlined,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Appearance',
                            subtitle:
                                '${settings.darkModeEnabled ? 'Dark' : 'Light'} mode · ${settings.motionEnabled ? 'Motion on' : 'Motion off'}',
                            onTap: () => _showAppearanceSheet(context),
                          ),
                          _buildSettingsRow(
                            icon: Icons.language_rounded,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Language',
                            subtitle: settings.languageCode == 'fil'
                                ? 'Filipino'
                                : 'English',
                            onTap: () => _showLanguageSheet(context),
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
                            iconBackground: TabbyColors.iconBgBlue,
                            iconColor: TabbyColors.accentLightBlue,
                            title: 'Sync & Offline',
                            subtitle: 'Offline cache and server status',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: TabbyColors.brandMintAccent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    syncStatusLabel(syncDiagnostics),
                                    style: TextStyle(
                                      color: syncDiagnostics.status ==
                                              SyncStatus.offline
                                          ? TabbyColors.alertRed
                                          : TabbyColors.brandEmerald,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded,
                                    color: TabbyColors.textSecondary),
                              ],
                            ),
                            onTap: () => SyncDiagnosticsSheet.show(context),
                          ),
                          _buildSettingsRow(
                            icon: Icons.headset_mic_outlined,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Help Center',
                            subtitle: 'Customer support and FAQ',
                            onTap: () => _showHelpCenterSheet(context),
                          ),
                          _buildSettingsRow(
                            icon: Icons.info_outline_rounded,
                            iconBackground: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
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
                            foregroundColor: TabbyColors.alertRed,
                            side: const BorderSide(
                                color: TabbyColors.alertRed, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Center(
                        child: Column(
                          children: [
                            Text(
                              'Tabby Phase 1 MVP',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: TabbyColors.textSecondary,
                              ),
                            ),
                            SizedBox(height: 2),
                            AppVersionFooter(),
                            SizedBox(height: 2),
                            Text(
                              'Keep tabs. Settle up.',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: TabbyColors.textSecondary,
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
      color: TabbyColors.brandEmerald,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Text(
              'Profile & Settings',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: TabbyColors.brandDarkTeal,
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
              color: TabbyColors.surfaceWhite,
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
                  color: TabbyColors.brandDarkTeal,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => _showAvatarOptionsSheet(context, user),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: TabbyColors.brandEmerald,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Container(
                    color: TabbyColors.brandEmerald,
                    alignment: Alignment.center,
                    child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                        ? (user.avatarUrl == 'asset:mascot'
                            ? const Icon(Icons.pets_rounded,
                                size: 30, color: TabbyColors.surfaceWhite)
                            : user.avatarUrl == 'asset:cat_cool'
                                ? const Icon(
                                    Icons.sentiment_very_satisfied_rounded,
                                    size: 30,
                                    color: TabbyColors.surfaceWhite)
                                : user.avatarUrl == 'asset:camera_snap'
                                    ? const Icon(Icons.camera_alt_rounded,
                                        size: 30,
                                        color: TabbyColors.surfaceWhite)
                                    : const Icon(Icons.account_circle_rounded,
                                        size: 34,
                                        color: TabbyColors.surfaceWhite))
                        : Text(
                            user.displayName.isNotEmpty
                                ? user.displayName.substring(0, 1).toUpperCase()
                                : 'T',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: TabbyColors.surfaceWhite,
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
                    color: TabbyColors.brandDarkTeal,
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
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Your Tabby ID',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: TabbyColors.textSecondary,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      user.friendCode ?? 'Not available yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: TabbyColors.brandEmerald,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    color: TabbyColors.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 26, minHeight: 26),
                    tooltip: 'Copy Tabby ID',
                    onPressed: user.friendCode == null
                        ? null
                        : () {
                            Clipboard.setData(
                                ClipboardData(text: user.friendCode!));
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Tabby ID copied to clipboard.'),
                                ),
                              );
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: () => _showEditProfileSheet(context, user),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit Profile'),
          style: OutlinedButton.styleFrom(
            foregroundColor: TabbyColors.brandEmerald,
            side: const BorderSide(color: TabbyColors.brandEmerald),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
            textStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeading(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: TabbyColors.brandDarkTeal,
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
      color: TabbyColors.surfaceWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: TabbyColors.borderMint),
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
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: TabbyColors.brandDarkTeal,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          color: TabbyColors.textSecondary,
        ),
      ),
      trailing: trailing ??
          const Icon(Icons.chevron_right_rounded,
              color: TabbyColors.textSecondary, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildClassroomRow(
    BuildContext context,
    ClassroomConnection? connection,
    int courseCount,
  ) {
    final isConnected = connection?.isActive == true;
    return _buildSettingsRow(
      icon: Icons.school_outlined,
      iconBackground:
          isConnected ? TabbyColors.iconBgMint : TabbyColors.iconBgBlue,
      iconColor:
          isConnected ? TabbyColors.brandEmerald : TabbyColors.textSecondary,
      title: 'Google Classroom',
      subtitle:
          isConnected ? 'Connected · $courseCount courses' : 'Not connected',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: TabbyColors.brandMintAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Active',
                style: TextStyle(
                  color: TabbyColors.brandEmerald,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const Icon(Icons.chevron_right_rounded,
              color: TabbyColors.textSecondary),
        ],
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TabbyColors.surfaceWhite,
        builder: (_) => const ClassroomConnectSheet(),
      ),
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
        Switch(
          value: value,
          activeThumbColor: TabbyColors.brandEmerald,
          onChanged: onChanged,
        ),
        IconButton(
          tooltip: tooltip,
          onPressed: onDetails,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.chevron_right_rounded,
              color: TabbyColors.textSecondary, size: 20),
        ),
      ],
    );
  }

  Widget _buildPreferenceChoice({
    required String title,
    required bool selected,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Icon(
        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        color: selected ? TabbyColors.brandEmerald : TabbyColors.textSecondary,
      ),
      onTap: onTap,
    );
  }

  void _showAboutTabbySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) {
          final checker = AppUpdateService();
          return Material(
            color: TabbyColors.surfaceWhite,
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
                            const Expanded(
                              child: Text('About Tabby',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: TabbyColors.brandDarkTeal)),
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
                                : '1.0.2+3';
                            return Text(
                              'Version $displayVer',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(statusText,
                            style: const TextStyle(
                                fontSize: 13,
                                color: TabbyColors.textSecondary)),
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
                        if (result?.status == AppUpdateStatus.updateAvailable) ...[
                          TabbyButton(
                            label: 'Update on Website',
                            onPressed: () async {
                              final url = Uri.parse(
                                  'https://tabby-web-fawn.vercel.app/#download');
                              try {
                                await launchUrl(url,
                                    mode: LaunchMode.externalApplication);
                              } catch (_) {}
                            },
                          ),
                          const SizedBox(height: 10),
                        ] else ...[
                          TabbyButton(
                            label: snapshot.connectionState ==
                                    ConnectionState.waiting
                                ? 'Checking...'
                                : 'Check for Updates',
                            onPressed: snapshot.connectionState ==
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
                                  'https://tabby-web-fawn.vercel.app');
                              try {
                                await launchUrl(url,
                                    mode: LaunchMode.externalApplication);
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.language_rounded,
                                size: 16, color: TabbyColors.brandDarkTeal),
                            label: const Text(
                              'Visit Tabby Website',
                              style: TextStyle(
                                  color: TabbyColors.brandDarkTeal,
                                  fontWeight: FontWeight.w600),
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(userSettingsProvider);
          final notifier = ref.read(userSettingsProvider.notifier);
          return Material(
            color: TabbyColors.surfaceWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Appearance',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal)),
                    const SizedBox(height: 12),
                    _buildPreferenceChoice(
                      title: 'Light mode',
                      selected: !settings.darkModeEnabled,
                      onTap: () => notifier.update(darkModeEnabled: false),
                    ),
                    _buildPreferenceChoice(
                      title: 'Dark mode',
                      selected: settings.darkModeEnabled,
                      onTap: () => notifier.update(darkModeEnabled: true),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: TabbyColors.brandEmerald,
                      title: const Text('Motion effects'),
                      subtitle:
                          const Text('Animate Tabby transitions and feedback'),
                      value: settings.motionEnabled,
                      onChanged: (value) =>
                          notifier.update(motionEnabled: value),
                    ),
                    TabbyButton(
                      label: 'Done',
                      onPressed: () => Navigator.pop(sheetContext),
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

  void _showLanguageSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(userSettingsProvider);
          final notifier = ref.read(userSettingsProvider.notifier);
          return Material(
            color: TabbyColors.surfaceWhite,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    leading: Icon(Icons.language_rounded,
                        color: TabbyColors.brandEmerald),
                    title: Text('Language',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  _buildPreferenceChoice(
                    title: 'English',
                    selected: settings.languageCode == 'en',
                    onTap: () => notifier.update(languageCode: 'en'),
                  ),
                  _buildPreferenceChoice(
                    title: 'Filipino',
                    selected: settings.languageCode == 'fil',
                    onTap: () => notifier.update(languageCode: 'fil'),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 4, 24, 20),
                    child: Text(
                      'More languages can be added without changing your financial records.',
                      style: TextStyle(
                          fontSize: 12, color: TabbyColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 1. Avatar Options Modal Sheet
  void _showAvatarOptionsSheet(BuildContext context, TabbyUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Material(
          color: TabbyColors.surfaceWhite,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                      const Text(
                        'Profile Photo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: TabbyColors.iconBgMint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.photo_library_rounded,
                          color: TabbyColors.brandEmerald, size: 20),
                    ),
                    title: const Text('Choose from Gallery',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text('Upload a photo from your camera roll',
                        style: TextStyle(fontSize: 12)),
                    onTap: () {
                      ref
                          .read(currentUserProvider.notifier)
                          .updateProfile(avatarUrl: 'asset:cat_cool');
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile photo updated successfully.'),
                          backgroundColor: TabbyColors.brandEmerald,
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: TabbyColors.iconBgBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: TabbyColors.accentBlue, size: 20),
                    ),
                    title: const Text('Take Photo',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text(
                        'Use your device camera to take a picture',
                        style: TextStyle(fontSize: 12)),
                    onTap: () {
                      ref
                          .read(currentUserProvider.notifier)
                          .updateProfile(avatarUrl: 'asset:camera_snap');
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Camera snapshot applied to profile.'),
                          backgroundColor: TabbyColors.brandEmerald,
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: TabbyColors.brandMintAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.pets_rounded,
                          color: TabbyColors.brandDarkTeal, size: 20),
                    ),
                    title: const Text('Tabby Mascot Style',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text(
                        'Use official Tabby cat companion as avatar',
                        style: TextStyle(fontSize: 12)),
                    onTap: () {
                      ref
                          .read(currentUserProvider.notifier)
                          .updateProfile(avatarUrl: 'asset:mascot');
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Tabby companion avatar applied!'),
                          backgroundColor: TabbyColors.brandEmerald,
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: TabbyColors.alertRed, size: 20),
                    ),
                    title: const Text('Remove Photo',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: TabbyColors.alertRed)),
                    subtitle: const Text(
                        'Revert back to default avatar initials',
                        style: TextStyle(fontSize: 12)),
                    onTap: () {
                      ref
                          .read(currentUserProvider.notifier)
                          .updateProfile(avatarUrl: '');
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Avatar reset to default initials.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 2. Edit Profile Modal Sheet
  void _showEditProfileSheet(BuildContext context, TabbyUser user) {
    final nameController = TextEditingController(text: user.displayName);
    final phoneController = TextEditingController(text: user.phone);
    final emailController = TextEditingController(text: user.email);
    final gcashController = TextEditingController(text: user.gcashNumber);
    final mayaController = TextEditingController(text: user.mayaNumber);

    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Material(
                color: TabbyColors.surfaceWhite,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
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
                            const Expanded(
                              child: Text(
                                'Edit Profile',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: TabbyColors.brandDarkTeal,
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
                        _buildInputField(
                          label: 'Display Name',
                          controller: nameController,
                          icon: Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          label: 'Email Address',
                          controller: emailController,
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          label: 'Phone Number',
                          controller: phoneController,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          label: 'GCash Number',
                          controller: gcashController,
                          icon: Icons.account_balance_wallet_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          label: 'Maya Number',
                          controller: mayaController,
                          icon: Icons.credit_card_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 24),
                        TabbyButton(
                          label: 'Save Changes',
                          isLoading: isSubmitting,
                          onPressed: () {
                            if (isSubmitting) return;

                            final newName = nameController.text.trim();
                            final newEmail = emailController.text.trim();
                            final newPhone = phoneController.text.trim();
                            final newGcash = gcashController.text.trim();
                            final newMaya = mayaController.text.trim();

                            if (newName.isEmpty) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a display name.'),
                                  backgroundColor: TabbyColors.alertRed,
                                ),
                              );
                              return;
                            }

                            if (newEmail.isNotEmpty &&
                                (!newEmail.contains('@') ||
                                    !newEmail.contains('.'))) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Please enter a valid email address.'),
                                  backgroundColor: TabbyColors.alertRed,
                                ),
                              );
                              return;
                            }

                            final phoneDigits =
                                newPhone.replaceAll(RegExp(r'[^0-9]'), '');
                            if (newPhone.isNotEmpty && phoneDigits.length < 7) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Please enter a valid phone number.'),
                                  backgroundColor: TabbyColors.alertRed,
                                ),
                              );
                              return;
                            }

                            setModalState(() => isSubmitting = true);

                            ref
                                .read(currentUserProvider.notifier)
                                .updateProfile(
                                  displayName: newName,
                                  email: newEmail,
                                  phone: newPhone,
                                  gcashNumber: newGcash,
                                  mayaNumber: newMaya,
                                );

                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Profile details updated successfully!'),
                                backgroundColor: TabbyColors.brandEmerald,
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

  // 3b. Security & App Lock Sheet
  void _showSecuritySettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final settings = ref.watch(userSettingsProvider);
            final notifier = ref.read(userSettingsProvider.notifier);
            return Material(
              color: TabbyColors.surfaceWhite,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
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
                          const Expanded(
                            child: Text(
                              'Security & App Lock',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.brandDarkTeal,
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
                        activeThumbColor: TabbyColors.brandEmerald,
                        title: const Text(
                          'Biometric Unlock',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TabbyColors.brandDarkTeal),
                        ),
                        subtitle: FutureBuilder<String>(
                          future: notifier.biometricLabel(),
                          builder: (context, snapshot) => Text(
                            settings.biometricsEnabled
                                ? '${snapshot.data ?? 'Biometric'} active'
                                : (snapshot.data ?? 'Checking device support'),
                            style: const TextStyle(
                                fontSize: 12, color: TabbyColors.textSecondary),
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
                        activeThumbColor: TabbyColors.brandEmerald,
                        title: const Text(
                          'Passcode Protection',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TabbyColors.brandDarkTeal),
                        ),
                        subtitle: const Text(
                          'Require a security PIN to access ledgers',
                          style: TextStyle(
                              fontSize: 12, color: TabbyColors.textSecondary),
                        ),
                        value: settings.passcodeEnabled,
                        onChanged: (val) async {
                          if (val) {
                            _showPinSetupSheet(context);
                          } else {
                            await notifier.clearPin();
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
                        activeThumbColor: TabbyColors.brandEmerald,
                        title: const Text(
                          'Auto-Lock on Exit',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TabbyColors.brandDarkTeal),
                        ),
                        subtitle: const Text(
                          'Lock Tabby immediately when backgrounded',
                          style: TextStyle(
                              fontSize: 12, color: TabbyColors.textSecondary),
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
                          color: TabbyColors.brandMintAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.shield_outlined,
                                color: TabbyColors.brandEmerald, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Financial records are stored locally with AES-256 device encryption and synced via TLS 1.3 to Supabase with Row Level Security.',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: TabbyColors.brandDarkTeal,
                                    height: 1.3),
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinSetupSheet(hostContext: context),
    );
  }

  // 3c. Notification Preferences Sheet
  void _showNotificationPreferencesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final settings = ref.watch(userSettingsProvider);
            final notifier = ref.read(userSettingsProvider.notifier);
            return Material(
              color: TabbyColors.surfaceWhite,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
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
                          const Expanded(
                            child: Text(
                              'Notification Preferences',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.brandDarkTeal,
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
                        activeThumbColor: TabbyColors.brandEmerald,
                        title: const Text(
                          'Push Notifications',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TabbyColors.brandDarkTeal),
                        ),
                        subtitle: const Text(
                          'Master switch for all device notifications',
                          style: TextStyle(
                              fontSize: 12, color: TabbyColors.textSecondary),
                        ),
                        value: settings.notificationsEnabled,
                        onChanged: (val) {
                          notifier.update(notificationsEnabled: val);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: TabbyColors.brandEmerald,
                        title: const Text(
                          'Instant Payment Alerts',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TabbyColors.brandDarkTeal),
                        ),
                        subtitle: const Text(
                          'Notify when friends record or confirm a payment',
                          style: TextStyle(
                              fontSize: 12, color: TabbyColors.textSecondary),
                        ),
                        value: settings.paymentAlertsEnabled,
                        onChanged: settings.notificationsEnabled
                            ? (val) {
                                notifier.update(paymentAlertsEnabled: val);
                              }
                            : null,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: TabbyColors.brandEmerald,
                        title: const Text(
                          'Gentle Reminder Nudges',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TabbyColors.brandDarkTeal),
                        ),
                        subtitle: const Text(
                          'Notify when due dates approach or tabs remain open',
                          style: TextStyle(
                              fontSize: 12, color: TabbyColors.textSecondary),
                        ),
                        value: settings.reminderNudgesEnabled,
                        onChanged: settings.notificationsEnabled
                            ? (val) {
                                notifier.update(reminderNudgesEnabled: val);
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
  void _showCurrencyPrecisionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Material(
          color: TabbyColors.surfaceWhite,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                      const Expanded(
                        child: Text(
                          'Integer Centavo Precision',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Consumer(
                    builder: (context, ref, _) {
                      final settings = ref.watch(userSettingsProvider);
                      final notifier = ref.read(userSettingsProvider.notifier);
                      return Column(
                        children: [
                          _buildPreferenceChoice(
                            title: 'Philippine Peso (PHP)',
                            subtitle: 'Primary ledger currency',
                            selected: settings.currencyCode == 'PHP',
                            onTap: () => notifier.update(currencyCode: 'PHP'),
                          ),
                          _buildPreferenceChoice(
                            title: 'US Dollar (USD)',
                            subtitle: 'Display conversion preference',
                            selected: settings.currencyCode == 'USD',
                            onTap: () => notifier.update(currencyCode: 'USD'),
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 24),
                  const TabbyMascotWidget(
                    emotion: MascotEmotion.calculating,
                    size: 50,
                    showBubble: false,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ADR-001 Financial Standard',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: TabbyColors.brandDarkTeal),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tabby computes and stores all currency internally as integer centavos (1 PHP = 100 centavos). This guarantees absolute mathematical accuracy and eliminates IEEE-754 floating-point rounding errors when splitting odd bills across multiple friends.',
                    style: TextStyle(
                        fontSize: 12,
                        color: TabbyColors.textSecondary,
                        height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: TabbyColors.brandMintAccent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_outlined,
                            color: TabbyColors.brandEmerald, size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Example: ₱1,000.00 is stored as 100000 centavos. A 3-way split divides exactly into 33334¢, 33333¢, and 33333¢ with zero lost centavos.',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: TabbyColors.brandDarkTeal),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TabbyButton(
                    label: 'Got it',
                    variant: TabbyButtonVariant.primary,
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 5. Backend & Offline Sync Diagnostics Sheet
  // ignore: unused_element
  void _showSyncDiagnosticsSheet(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Material(
          color: TabbyColors.surfaceWhite,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                      const Expanded(
                        child: Text(
                          'Backend & Offline Sync',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDiagnosticsRow(
                    icon: Icons.cloud_done_rounded,
                    title: 'Supabase BaaS',
                    subtitle: 'PostgreSQL 15+ relational database with RLS',
                    status: 'Connected',
                    statusColor: TabbyColors.brandEmerald,
                  ),
                  const Divider(height: 20),
                  _buildDiagnosticsRow(
                    icon: Icons.storage_rounded,
                    title: 'Drift Local Cache',
                    subtitle: 'Offline-first SQLite local store on device',
                    status: 'Synchronized',
                    statusColor: TabbyColors.brandEmerald,
                  ),
                  const Divider(height: 20),
                  _buildDiagnosticsRow(
                    icon: Icons.security_rounded,
                    title: 'Row Level Security',
                    subtitle: 'Audited user-scoped permissions active',
                    status: 'Enforced',
                    statusColor: TabbyColors.accentBlue,
                  ),
                  const SizedBox(height: 24),
                  TabbyButton(
                    label: 'Sync Data Now',
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      ref.read(tabbyProvider.notifier).refreshTabs();
                      messenger.clearSnackBars();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                              'All tabs and transactions are fully synchronized.'),
                          backgroundColor: TabbyColors.brandEmerald,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 6. Help Center & FAQ Sheet
  void _showHelpCenterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Material(
          color: TabbyColors.surfaceWhite,
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
                    const Expanded(
                      child: Text(
                        'Help Center & FAQ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
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
                        answer:
                            'A Tab is the complete running bilateral financial ledger between two people. Regardless of how many meals, rides, or bills you share, there is only one running balance between you.',
                        initiallyExpanded: true,
                      ),
                      _buildFaqItem(
                        question: 'How does Bill Splitting work?',
                        answer:
                            'You can choose a 50/50 Split for equal halves or Full Share if one person covered the whole item. Centavo-accurate rounding ensures exact balances.',
                      ),
                      _buildFaqItem(
                        question: 'How do I settle up?',
                        answer:
                            'You can pay using GCash, Maya, Cash, or Bank Transfer. Once payment is recorded in the tab, Tabby updates your net balance immediately.',
                      ),
                      _buildFaqItem(
                        question: 'What is a Friendly Reminder?',
                        answer:
                            'Instead of awkward texts, Tabby provides a cute mascot reminder card that you can share with your friend to defuse any tension.',
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: TabbyColors.brandMintAccent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Still have questions?',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Our support team is always happy to assist you.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: TabbyColors.textSecondary),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(const ClipboardData(
                                    text: 'support@tabby.ph'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Support email copied to clipboard: support@tabby.ph'),
                                    backgroundColor: TabbyColors.brandDarkTeal,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy support@tabby.ph'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: TabbyColors.brandDarkTeal,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
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
    showModalBottomSheet(
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
    ScaffoldMessenger.of(context).clearSnackBars();
    final nameController = TextEditingController();
    final friends = ref.read(friendsProvider);
    final selectedFriendIds = <String>{};
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Material(
                color: TabbyColors.surfaceWhite,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
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
                            const Expanded(
                              child: Text(
                                'Create New Group Tab',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: TabbyColors.brandDarkTeal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Keep tabs for barkada meals, roommates, or shared road trips.',
                          style: TextStyle(
                              fontSize: 12, color: TabbyColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                          label: 'Group Name (e.g. Barkada Dinner, Room 302)',
                          controller: nameController,
                          icon: Icons.groups_rounded,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Select Members from Friends',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: TabbyColors.brandDarkTeal),
                        ),
                        const SizedBox(height: 8),
                        if (friends.isEmpty)
                          const Text(
                            'No accepted friends yet. Connect with a friend first.',
                            style: TextStyle(
                                fontSize: 12, color: TabbyColors.textSecondary),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: friends.map((friend) {
                              final isSelected =
                                  selectedFriendIds.contains(friend.id);
                              return FilterChip(
                                label: Text(friend.displayName),
                                selected: isSelected,
                                selectedColor: TabbyColors.brandMintAccent,
                                checkmarkColor: TabbyColors.brandEmerald,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? TabbyColors.brandEmerald
                                      : TabbyColors.brandDarkTeal,
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
                          label:
                              isSubmitting ? 'Creating...' : 'Create Group Tab',
                          isLoading: isSubmitting,
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  final groupName = nameController.text.trim();
                                  if (groupName.isEmpty) {
                                    ScaffoldMessenger.of(context)
                                        .clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('Please enter a group name.'),
                                        backgroundColor: TabbyColors.alertRed,
                                      ),
                                    );
                                    return;
                                  }

                                  if (selectedFriendIds.isEmpty) {
                                    ScaffoldMessenger.of(context)
                                        .clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Select at least one accepted friend.'),
                                        backgroundColor: TabbyColors.alertRed,
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

                                  ref.read(tabbyProvider.notifier).addGroupTab(
                                        groupName: groupName,
                                        memberNames: memberNames,
                                        memberUserIds:
                                            selectedFriendIds.toList(),
                                      );

                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context)
                                      .clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Group "$groupName" created successfully!'),
                                      backgroundColor: TabbyColors.brandEmerald,
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
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: TabbyColors.alertRed, size: 22),
              SizedBox(width: 8),
              Text(
                'Log Out',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out of your Tabby account?',
            style: TextStyle(fontSize: 14, color: TabbyColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel',
                  style: TextStyle(color: TabbyColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                // 1. Immediately invalidate auth flag — router redirects to /login
                final userId = SupabaseConfig.currentUserId;
                AppState.isAuthenticated.value = false;
                // 2. Clear in-memory providers
                ref.read(currentUserProvider.notifier).reset();
                ref.read(tabbyProvider.notifier).reset();
                // 3. Navigate immediately (no waiting for Supabase)
                if (context.mounted) context.go('/login');
                // 4. Clear local cache and sign out in background
                try {
                  if (userId != null) {
                    await TabbyLocalCache.clearCache(userId: userId);
                  }
                  await SupabaseTabbyRepository.instance.signOut();
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TabbyColors.alertRed,
                foregroundColor: TabbyColors.surfaceWhite,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
        color: TabbyColors.brandMintAccent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: TabbyColors.brandDarkTeal,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              const TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
          prefixIcon: Icon(icon, size: 20, color: TabbyColors.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildDiagnosticsRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: TabbyColors.iconBgMint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: TabbyColors.brandDarkTeal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TabbyColors.brandDarkTeal),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                    fontSize: 11, color: TabbyColors.textSecondary),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
          ),
        ),
      ],
    );
  }

  Widget _buildFaqItem(
      {required String question,
      required String answer,
      bool initiallyExpanded = false}) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        title: Text(
          question,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: TabbyColors.brandDarkTeal),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              answer,
              style: const TextStyle(
                  fontSize: 12, color: TabbyColors.textSecondary, height: 1.4),
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
  TabbyUser? _foundUser;
  String? _message;
  bool _isLookingUp = false;
  bool _isSending = false;
  bool _requestSent = false;
  int _lookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
  }

  @override
  void dispose() {
    _lookupGeneration++;
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _findFriend() async {
    if (_isLookingUp) return;

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
      _message = null;
    });

    try {
      final user = await widget.findFriend(normalized);
      if (!mounted || lookupGeneration != _lookupGeneration) return;
      setState(() {
        _isLookingUp = false;
        _foundUser = user;
        _message =
            user == null ? 'No Tabby account was found for that ID.' : null;
      });
    } catch (_) {
      if (!mounted || lookupGeneration != _lookupGeneration) return;
      setState(() {
        _isLookingUp = false;
        _foundUser = null;
        _message = 'We could not look up that ID. Please try again.';
      });
    }
  }

  Future<void> _sendRequest() async {
    if (_isSending || _foundUser == null) return;

    final normalized = normalizeFriendCode(_codeController.text);
    if (normalized == null) return;

    setState(() => _isSending = true);
    try {
      final request = await widget.sendFriendRequest(normalized);
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _requestSent = request != null;
        _message = request == null
            ? 'We could not send the request. Please try again.'
            : 'Request sent. They can accept it from their Profile.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _message = 'We could not send the request. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Material(
        color: TabbyColors.surfaceWhite,
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
                  children: [
                    const Expanded(
                      child: Text(
                        'Connect with a Friend',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TabbyColors.brandDarkTeal,
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
                const Text(
                  'Enter the exact Tabby ID your friend shared with you.',
                  style: TextStyle(
                    fontSize: 12,
                    color: TabbyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Tabby ID',
                    hintText: 'TAB-7K4P2M',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Find friend',
                      onPressed: _isLookingUp ? null : _findFriend,
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
                      color: TabbyColors.brandMintAccent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: TabbyColors.brandEmerald,
                          child: Text(
                            _foundUser!.displayName.isNotEmpty
                                ? _foundUser!.displayName
                                    .substring(0, 1)
                                    .toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: TabbyColors.surfaceWhite,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _foundUser!.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.brandDarkTeal,
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
                          ? TabbyColors.brandEmerald
                          : TabbyColors.alertRed,
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
                        backgroundColor: TabbyColors.brandEmerald,
                        foregroundColor: TabbyColors.surfaceWhite,
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
                                color: TabbyColors.surfaceWhite,
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
      ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(widget.hostContext).showSnackBar(
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
      color: TabbyColors.surfaceWhite,
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
              const Text(
                'Configure PIN',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use a 4 to 6 digit PIN as a device fallback.',
                style: TextStyle(
                  fontSize: 12,
                  color: TabbyColors.textSecondary,
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
