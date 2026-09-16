import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_state.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/notification_center_sheet.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../../tabs/domain/models.dart';
import '../../tabs/presentation/add_expense_modal.dart';

typedef FriendLookup = Future<TabbyUser?> Function(String friendCode);
typedef FriendRequestSubmitter = Future<FriendRequest?> Function(String friendCode);

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String? _respondingFriendshipId;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(groupsProvider);
    final incomingRequests = ref.watch(tabbyProvider).friendRequests.where(
          (request) =>
              request.isIncoming && request.status == FriendRequestStatus.pending,
        ).toList();
    final settings = ref.watch(userSettingsProvider);
    final settingsNotifier = ref.read(userSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: TabbyColors.brandEmerald,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Green Header Section (Figma profile_7020_3844)
            Container(
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
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        size: 22,
                        color: TabbyColors.brandDarkTeal,
                      ),
                      onPressed: () => NotificationCenterSheet.show(context),
                      tooltip: 'Notifications',
                    ),
                  ),
                ],
              ),
            ),

            // Main Curved Body with Center Avatar (Figma profile_7020_3844)
            Expanded(
              child: Material(
                color: TabbyColors.bgCanvas,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  child: Column(
                    children: [
                      // Center Avatar Card (Figma profile_7020_3844)
                      Center(
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: () => _showAvatarOptionsSheet(context, user),
                              child: Stack(
                                children: [
                                  Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: TabbyColors.brandEmerald, width: 3.5),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: Container(
                                        color: TabbyColors.brandEmerald,
                                        child: Center(
                                          child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                                              ? (user.avatarUrl == 'asset:mascot'
                                                  ? const Icon(Icons.pets_rounded, size: 44, color: TabbyColors.surfaceWhite)
                                                  : user.avatarUrl == 'asset:cat_cool'
                                                      ? const Icon(Icons.sentiment_very_satisfied_rounded, size: 44, color: TabbyColors.surfaceWhite)
                                                      : user.avatarUrl == 'asset:camera_snap'
                                                          ? const Icon(Icons.camera_alt_rounded, size: 44, color: TabbyColors.surfaceWhite)
                                                          : const Icon(Icons.account_circle_rounded, size: 48, color: TabbyColors.surfaceWhite))
                                              : Text(
                                                  user.displayName.isNotEmpty
                                                      ? user.displayName.substring(0, 1).toUpperCase()
                                                      : 'T',
                                                  style: const TextStyle(
                                                    fontSize: 36,
                                                    fontWeight: FontWeight.w900,
                                                    color: TabbyColors.surfaceWhite,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: TabbyColors.brandDarkTeal,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 14,
                                        color: TabbyColors.surfaceWhite,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              user.displayName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.brandDarkTeal,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.friendCode == null
                                  ? 'Tabby ID not available yet'
                                  : 'Tabby ID: ${user.friendCode}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: TabbyColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${user.phone} • ${user.email}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: TabbyColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Shareable account ID card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: TabbyColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: TabbyColors.borderMint),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: TabbyColors.iconBgBlue,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.badge_outlined,
                                    color: TabbyColors.accentLightBlue,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Your Tabby ID',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: TabbyColors.brandDarkTeal,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Copy Tabby ID',
                                  onPressed: user.friendCode == null
                                      ? null
                                      : () {
                                          Clipboard.setData(
                                            ClipboardData(text: user.friendCode!),
                                          );
                                          ScaffoldMessenger.of(context)
                                            ..clearSnackBars()
                                            ..showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Tabby ID copied to clipboard.',
                                                ),
                                              ),
                                            );
                                        },
                                  icon: const Icon(Icons.copy_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              user.friendCode ??
                                  'Your shareable ID will appear after your account is synced.',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: TabbyColors.brandEmerald,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Share this ID with friends so they can connect with you without using account details.',
                              style: TextStyle(
                                fontSize: 11,
                                color: TabbyColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _showConnectByIdSheet(context),
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: const Text('Connect by Tabby ID'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: TabbyColors.brandEmerald,
                                side: const BorderSide(
                                  color: TabbyColors.brandEmerald,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (incomingRequests.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Friend Requests',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.brandDarkTeal,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Material(
                          color: TabbyColors.surfaceWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: TabbyColors.borderMint),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: incomingRequests.map((request) {
                              final isResponding =
                                  _respondingFriendshipId == request.id;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: TabbyColors.iconBgBlue,
                                  child: Text(
                                    request.otherUser.displayName.isNotEmpty
                                        ? request.otherUser.displayName
                                            .substring(0, 1)
                                            .toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: TabbyColors.accentLightBlue,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  request.otherUser.displayName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: TabbyColors.brandDarkTeal,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Wants to connect a shared tab with you.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: TabbyColors.textSecondary,
                                  ),
                                ),
                                trailing: isResponding
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            tooltip: 'Decline request',
                                            onPressed: () =>
                                                _respondToFriendRequest(
                                              request,
                                              accept: false,
                                            ),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              color: TabbyColors.textSecondary,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Accept request',
                                            onPressed: () =>
                                                _respondToFriendRequest(
                                              request,
                                              accept: true,
                                            ),
                                            icon: const Icon(
                                              Icons.check_rounded,
                                              color: TabbyColors.brandEmerald,
                                            ),
                                          ),
                                        ],
                                      ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      // Payment QR Ph Card (Figma / FinWise)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: TabbyColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: TabbyColors.borderMint),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x04000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: TabbyColors.iconBgMint,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.qr_code_2_rounded,
                                          color: TabbyColors.brandEmerald,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          'My Payment QR Ph',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: TabbyColors.brandDarkTeal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: TabbyColors.brandMintAccent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'GCash / Maya',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: TabbyColors.brandDarkTeal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () => _showQrManagerSheet(context, user),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: TabbyColors.brandMintAccent,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                            ? Icons.qr_code_2_rounded
                                            : Icons.add_a_photo_outlined,
                                        size: 28,
                                        color: user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                            ? TabbyColors.brandEmerald
                                            : TabbyColors.brandDarkTeal,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                            ? 'Custom QR Ph Code Active & Verified'
                                            : (user.gcashNumber.isNotEmpty || user.mayaNumber.isNotEmpty
                                                ? 'GCash: ${user.gcashNumber.isNotEmpty ? user.gcashNumber : 'Not set'} • Maya: ${user.mayaNumber.isNotEmpty ? user.mayaNumber : 'Not set'}'
                                                : 'Upload your GCash or Maya QR Ph code'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                              ? TabbyColors.brandEmerald
                                              : TabbyColors.brandDarkTeal,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      TextButton(
                                        onPressed: () => _showQrManagerSheet(context, user),
                                        child: Text(
                                          user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                              ? 'Edit Payment QR Code'
                                              : 'Manage Payment QR Code',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: TabbyColors.brandEmerald,
                                          ),
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
                      const SizedBox(height: 16),

                      // Settings & Menu List (Figma profile_7020_3844 menu style)
                      Material(
                        color: TabbyColors.surfaceWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: TabbyColors.borderMint),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _buildProfileMenuItem(
                              icon: Icons.person_rounded,
                              iconBg: TabbyColors.iconBgBlue,
                              iconColor: TabbyColors.accentLightBlue,
                              title: 'Edit Profile',
                              subtitle: 'Name, phone, and account details',
                              onTap: () => _showEditProfileSheet(context, user),
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              secondary: IconButton(
                                icon: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: TabbyColors.iconBgMint,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.security_rounded, color: TabbyColors.brandEmerald, size: 20),
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: 'Security Settings',
                                onPressed: () => _showSecuritySettingsSheet(context),
                              ),
                              title: const Text(
                                'Security',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                              ),
                              subtitle: Text(
                                settings.biometricsEnabled ? 'Biometric security active' : 'Biometric security disabled',
                                style: const TextStyle(fontSize: 11, color: TabbyColors.textSecondary),
                              ),
                              value: settings.biometricsEnabled,
                              activeThumbColor: TabbyColors.brandEmerald,
                              onChanged: (val) {
                                settingsNotifier.update(biometricsEnabled: val);
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(val ? 'Biometric security enabled.' : 'Biometric security disabled.'),
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              secondary: IconButton(
                                icon: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: TabbyColors.iconBgBlue,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.settings_rounded, color: TabbyColors.accentLightBlue, size: 20),
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: 'Notification Preferences',
                                onPressed: () => _showNotificationPreferencesSheet(context),
                              ),
                              title: const Text(
                                'Settings',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                              ),
                              subtitle: Text(
                                settings.notificationsEnabled ? 'Push notifications and reminders active' : 'Notifications paused',
                                style: const TextStyle(fontSize: 11, color: TabbyColors.textSecondary),
                              ),
                              value: settings.notificationsEnabled,
                              activeThumbColor: TabbyColors.brandEmerald,
                              onChanged: (val) {
                                settingsNotifier.update(notificationsEnabled: val);
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(val ? 'Notifications enabled.' : 'Notifications disabled.'),
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
                                  color: TabbyColors.iconBgMint,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.currency_exchange_rounded,
                                  color: TabbyColors.brandEmerald,
                                  size: 20,
                                ),
                              ),
                              title: const Text(
                                'Currency Precision',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal,
                                ),
                              ),
                              subtitle: const Text(
                                'Philippine Peso (PHP) • Integer Centavos (ADR-001)',
                                style: TextStyle(fontSize: 11, color: TabbyColors.textSecondary),
                              ),
                              trailing: const Text(
                                '100¢ = ₱1.00',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: TabbyColors.brandEmerald,
                                ),
                              ),
                              onTap: () => _showCurrencyPrecisionSheet(context),
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
                                child: const Icon(
                                  Icons.cloud_done_rounded,
                                  color: TabbyColors.accentLightBlue,
                                  size: 20,
                                ),
                              ),
                              title: const Text(
                                'Backend & Offline Sync',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: TabbyColors.brandDarkTeal,
                                ),
                              ),
                              subtitle: const Text(
                                'Supabase BaaS and Drift local cache',
                                style: TextStyle(fontSize: 11, color: TabbyColors.textSecondary),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: TabbyColors.brandMintAccent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Online',
                                  style: TextStyle(
                                    color: TabbyColors.brandEmerald,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              onTap: () => _showSyncDiagnosticsSheet(context),
                            ),
                            const Divider(height: 1),
                            _buildProfileMenuItem(
                              icon: Icons.headset_mic_rounded,
                              iconBg: TabbyColors.iconBgMint,
                              iconColor: TabbyColors.brandEmerald,
                              title: 'Help Center',
                              subtitle: 'Customer support and FAQ',
                              onTap: () => _showHelpCenterSheet(context),
                            ),
                            const Divider(height: 1),
                            _buildProfileMenuItem(
                              icon: Icons.logout_rounded,
                              iconBg: const Color(0xFFFEE2E2),
                              iconColor: TabbyColors.alertRed,
                              title: 'Logout',
                              subtitle: 'Sign out of current account',
                              onTap: () => _showLogoutConfirmation(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Friends List Section Header
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 8,
                        children: [
                          const Text(
                            'Friends',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.brandDarkTeal,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${friends.length} ${friends.length == 1 ? 'friend' : 'friends'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: TabbyColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _showConnectByIdSheet(context),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: TabbyColors.brandMintAccent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.person_add_rounded,
                                        size: 14,
                                        color: TabbyColors.brandEmerald,
                                      ),
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
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (friends.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          decoration: BoxDecoration(
                            color: TabbyColors.surfaceWhite,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: TabbyColors.borderMint),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.people_outline_rounded,
                                  size: 36,
                                  color: TabbyColors.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'No friends added yet',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: TabbyColors.brandDarkTeal,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Connect with friends using their shareable Tabby ID.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: TabbyColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _showConnectByIdSheet(context),
                                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                                  label: const Text('Connect by Tabby ID'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: TabbyColors.brandEmerald,
                                    foregroundColor: TabbyColors.surfaceWhite,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Material(
                          color: TabbyColors.surfaceWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: TabbyColors.borderMint),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: friends.map((friend) {
                              return Column(
                                children: [
                                  ListTile(
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: TabbyColors.iconBgBlue,
                                      child: Text(
                                        friend.displayName.isNotEmpty
                                            ? friend.displayName.substring(0, 1).toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: TabbyColors.accentLightBlue,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      friend.displayName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: TabbyColors.brandDarkTeal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      friend.friendCode?.isNotEmpty == true
                                          ? 'Connected'
                                          : (friend.phone.isNotEmpty
                                              ? friend.phone
                                              : 'Saved contact'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: TabbyColors.textSecondary,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.more_vert_rounded,
                                        color: TabbyColors.textSecondary,
                                        size: 20,
                                      ),
                                      onPressed: () => _showFriendOptionsSheet(context, friend),
                                    ),
                                    onTap: () {
                                      context.go('/tabs/${friend.id}');
                                    },
                                  ),
                                  if (friend != friends.last)
                                    const Divider(height: 1),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Groups Section Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Groups',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.brandDarkTeal,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${groups.length} ${groups.length == 1 ? 'group' : 'groups'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: TabbyColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _showCreateGroupSheet(context),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: TabbyColors.brandMintAccent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.group_add_rounded,
                                        size: 14,
                                        color: TabbyColors.brandEmerald,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'New Group',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: TabbyColors.brandEmerald,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (groups.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          decoration: BoxDecoration(
                            color: TabbyColors.surfaceWhite,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: TabbyColors.borderMint),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.groups_outlined,
                                  size: 36,
                                  color: TabbyColors.textSecondary,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'No group tabs yet',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: TabbyColors.brandDarkTeal,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Create a group tab for barkada dinners, trips, or roommate expenses.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: TabbyColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _showCreateGroupSheet(context),
                                  icon: const Icon(Icons.group_add_rounded, size: 16),
                                  label: const Text('Create a Group'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: TabbyColors.brandEmerald,
                                    foregroundColor: TabbyColors.surfaceWhite,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Material(
                          color: TabbyColors.surfaceWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: TabbyColors.borderMint),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: groups.map((group) {
                              return Column(
                                children: [
                                  ListTile(
                                    leading: const CircleAvatar(
                                      radius: 18,
                                      backgroundColor: TabbyColors.brandMintAccent,
                                      child: Icon(
                                        Icons.groups_rounded,
                                        size: 18,
                                        color: TabbyColors.brandEmerald,
                                      ),
                                    ),
                                    title: Text(
                                      group.groupName ?? group.counterpart.displayName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: TabbyColors.brandDarkTeal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      group.counterpart.phone.isNotEmpty
                                          ? group.counterpart.phone
                                          : 'Group Tab',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: TabbyColors.textSecondary,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.more_vert_rounded,
                                        color: TabbyColors.textSecondary,
                                        size: 20,
                                      ),
                                      onPressed: () => _showGroupOptionsSheet(context, group),
                                    ),
                                    onTap: () {
                                      context.go('/tabs/${group.id}');
                                    },
                                  ),
                                  if (group != groups.last)
                                    const Divider(height: 1),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Version & App Info Footer
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

  Widget _buildProfileMenuItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: TabbyColors.brandDarkTeal,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: TabbyColors.textSecondary),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: TabbyColors.textSecondary, size: 20),
      onTap: onTap,
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
                    child: const Icon(Icons.photo_library_rounded, color: TabbyColors.brandEmerald, size: 20),
                  ),
                  title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text('Upload a photo from your camera roll', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    ref.read(currentUserProvider.notifier).updateProfile(avatarUrl: 'asset:cat_cool');
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
                    child: const Icon(Icons.camera_alt_rounded, color: TabbyColors.accentBlue, size: 20),
                  ),
                  title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text('Use your device camera to take a picture', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    ref.read(currentUserProvider.notifier).updateProfile(avatarUrl: 'asset:camera_snap');
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
                    child: const Icon(Icons.pets_rounded, color: TabbyColors.brandDarkTeal, size: 20),
                  ),
                  title: const Text('Tabby Mascot Style', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text('Use official Tabby cat companion as avatar', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    ref.read(currentUserProvider.notifier).updateProfile(avatarUrl: 'asset:mascot');
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
                    child: const Icon(Icons.delete_outline_rounded, color: TabbyColors.alertRed, size: 20),
                  ),
                  title: const Text('Remove Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: TabbyColors.alertRed)),
                  subtitle: const Text('Revert back to default avatar initials', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    ref.read(currentUserProvider.notifier).updateProfile(avatarUrl: '');
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
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Material(
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

                            if (newEmail.isNotEmpty && (!newEmail.contains('@') || !newEmail.contains('.'))) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a valid email address.'),
                                  backgroundColor: TabbyColors.alertRed,
                                ),
                              );
                              return;
                            }

                            final phoneDigits = newPhone.replaceAll(RegExp(r'[^0-9]'), '');
                            if (newPhone.isNotEmpty && phoneDigits.length < 7) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a valid phone number.'),
                                  backgroundColor: TabbyColors.alertRed,
                                ),
                              );
                              return;
                            }

                            setModalState(() => isSubmitting = true);

                            ref.read(currentUserProvider.notifier).updateProfile(
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
                                content: Text('Profile details updated successfully!'),
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

  // 3. QR Manager Modal Sheet
  void _showQrManagerSheet(BuildContext context, TabbyUser user) {
    final gcashController = TextEditingController(text: user.gcashNumber.isNotEmpty ? user.gcashNumber : user.phone);
    final mayaController = TextEditingController(text: user.mayaNumber.isNotEmpty ? user.mayaNumber : user.phone);

    bool isUploading = false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Material(
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
                                'Payment QR Ph Settings',
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
                        Center(
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              color: TabbyColors.brandMintAccent,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                    ? TabbyColors.brandEmerald
                                    : TabbyColors.borderMint,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isUploading)
                                  const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation(TabbyColors.brandEmerald),
                                    ),
                                  )
                                else ...[
                                  Icon(
                                    Icons.qr_code_2_rounded,
                                    size: 64,
                                    color: user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                        ? TabbyColors.brandEmerald
                                        : TabbyColors.brandDarkTeal,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                        ? 'QR Ph Active'
                                        : 'No QR Linked',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty
                                          ? TabbyColors.brandEmerald
                                          : TabbyColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
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
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: isUploading || isSaving
                              ? null
                              : () async {
                                  setModalState(() => isUploading = true);
                                  await Future.delayed(const Duration(milliseconds: 300));
                                  final simulatedQrUrl = 'https://tabby.ph/qr/${user.id}_qrph.png';
                                  ref.read(currentUserProvider.notifier).updateProfile(
                                        qrCodeUrl: simulatedQrUrl,
                                        gcashNumber: gcashController.text.trim(),
                                        mayaNumber: mayaController.text.trim(),
                                      );
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Payment QR Ph code verified and linked!'),
                                        backgroundColor: TabbyColors.brandEmerald,
                                      ),
                                    );
                                  }
                                },
                          icon: isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file_rounded, size: 18),
                          label: Text(isUploading ? 'Verifying QR Code...' : 'Upload New QR Code Image'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TabbyColors.brandDarkTeal,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        if (user.qrCodeUrl != null && user.qrCodeUrl!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () {
                              ref.read(currentUserProvider.notifier).updateProfile(
                                    qrCodeUrl: '',
                                    gcashNumber: gcashController.text.trim(),
                                    mayaNumber: mayaController.text.trim(),
                                  );
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Custom QR code removed.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: TabbyColors.alertRed),
                            label: const Text('Remove QR Code', style: TextStyle(color: TabbyColors.alertRed)),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TabbyButton(
                          label: 'Save Payment Details',
                          isLoading: isSaving,
                          onPressed: () {
                            if (isSaving || isUploading) return;

                            final gcash = gcashController.text.trim();
                            final maya = mayaController.text.trim();

                            final gcashDigits = gcash.replaceAll(RegExp(r'[^0-9]'), '');
                            if (gcash.isNotEmpty && gcashDigits.length < 10) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a valid GCash mobile number (at least 10 digits).'),
                                  backgroundColor: TabbyColors.alertRed,
                                ),
                              );
                              return;
                            }

                            final mayaDigits = maya.replaceAll(RegExp(r'[^0-9]'), '');
                            if (maya.isNotEmpty && mayaDigits.length < 10) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a valid Maya mobile number (at least 10 digits).'),
                                  backgroundColor: TabbyColors.alertRed,
                                ),
                              );
                              return;
                            }

                            setModalState(() => isSaving = true);

                            ref.read(currentUserProvider.notifier).updateProfile(
                                  gcashNumber: gcash,
                                  mayaNumber: maya,
                                );
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Payment QR and numbers saved!'),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                      ),
                      subtitle: const Text(
                        'Use fingerprint or Face ID to unlock Tabby',
                        style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                      ),
                      subtitle: const Text(
                        'Require a security PIN to access ledgers',
                        style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
                      ),
                      value: settings.passcodeEnabled,
                      onChanged: (val) {
                        notifier.update(passcodeEnabled: val);
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: TabbyColors.brandEmerald,
                      title: const Text(
                        'Auto-Lock on Exit',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                      ),
                      subtitle: const Text(
                        'Lock Tabby immediately when backgrounded',
                        style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
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
                          Icon(Icons.shield_outlined, color: TabbyColors.brandEmerald, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Financial records are stored locally with AES-256 device encryption and synced via TLS 1.3 to Supabase with Row Level Security.',
                              style: TextStyle(fontSize: 11, color: TabbyColors.brandDarkTeal, height: 1.3),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                      ),
                      subtitle: const Text(
                        'Master switch for all device notifications',
                        style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                      ),
                      subtitle: const Text(
                        'Notify when friends record or confirm a payment',
                        style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
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
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                      ),
                      subtitle: const Text(
                        'Notify when due dates approach or tabs remain open',
                        style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
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
                  const TabbyMascotWidget(
                    emotion: MascotEmotion.calculating,
                    size: 50,
                    showBubble: false,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ADR-001 Financial Standard',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tabby computes and stores all currency internally as integer centavos (1 PHP = 100 centavos). This guarantees absolute mathematical accuracy and eliminates IEEE-754 floating-point rounding errors when splitting odd bills across multiple friends.',
                    style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary, height: 1.5),
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
                        Icon(Icons.verified_outlined, color: TabbyColors.brandEmerald, size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Example: ₱1,000.00 is stored as 100000 centavos. A 3-way split divides exactly into 33334¢, 33333¢, and 33333¢ with zero lost centavos.',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TabbyColors.brandDarkTeal),
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
                          content: Text('All tabs and transactions are fully synchronized.'),
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
                          color: TabbyColors.brandMintAccent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Still have questions?',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Our support team is always happy to assist you.',
                              style: TextStyle(fontSize: 11, color: TabbyColors.textSecondary),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(const ClipboardData(text: 'support@tabby.ph'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Support email copied to clipboard: support@tabby.ph'),
                                    backgroundColor: TabbyColors.brandDarkTeal,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy support@tabby.ph'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: TabbyColors.brandDarkTeal,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Future<void> _respondToFriendRequest(
    FriendRequest request, {
    required bool accept,
  }) async {
    setState(() => _respondingFriendshipId = request.id);
    final success = await ref.read(tabbyProvider.notifier).respondToFriendRequest(
          friendshipId: request.id,
          accept: accept,
        );
    if (!mounted) return;

    setState(() => _respondingFriendshipId = null);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (accept
                    ? 'Friend request accepted. Your shared tab is ready.'
                    : 'Friend request declined.')
                : 'We could not update that request. Please try again.',
          ),
        ),
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

  // 7b. Friend Options Sheet
  void _showFriendOptionsSheet(BuildContext context, TabbyUser friend) {
    ScaffoldMessenger.of(context).clearSnackBars();
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              friend.displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.brandDarkTeal,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              friend.friendCode?.isNotEmpty == true
                                  ? 'Connected'
                                  : (friend.phone.isNotEmpty
                                      ? friend.phone
                                      : 'Saved contact'),
                              style: const TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
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
                      child: const Icon(Icons.receipt_long_rounded, color: TabbyColors.brandEmerald, size: 20),
                    ),
                    title: const Text('Open Ledger & Tab', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text('View running balance and transaction history', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      context.go('/tabs/${friend.id}');
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
                      child: const Icon(Icons.add_circle_outline_rounded, color: TabbyColors.accentBlue, size: 20),
                    ),
                    title: const Text('Log Shared Expense', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text('Split a new bill or record an expense', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      AddExpenseModal.show(context, initialCounterpartId: friend.id);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: TabbyColors.iconBgMint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_outlined, color: TabbyColors.brandEmerald, size: 20),
                    ),
                    title: const Text('Edit Friend Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text('Update name, mobile, or payment numbers', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showEditFriendSheet(context, friend);
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
                      child: const Icon(Icons.person_remove_rounded, color: TabbyColors.alertRed, size: 20),
                    ),
                    title: const Text('Remove Friend', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: TabbyColors.alertRed)),
                    subtitle: const Text('Remove from your friends list', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showRemoveFriendConfirmation(context, friend);
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

  // 7c. Edit Friend Details Sheet
  void _showEditFriendSheet(BuildContext context, TabbyUser friend) {
    ScaffoldMessenger.of(context).clearSnackBars();
    final nameController = TextEditingController(text: friend.displayName);
    final phoneController = TextEditingController(text: friend.phone);
    final emailController = TextEditingController(text: friend.email);
    final gcashController = TextEditingController(text: friend.gcashNumber);
    final mayaController = TextEditingController(text: friend.mayaNumber);
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Material(
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
                                'Edit Friend Details',
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
                        _buildInputField(
                          label: 'Friend\'s Full Name',
                          controller: nameController,
                          icon: Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          label: 'Mobile Number (+63 9XX XXX XXXX)',
                          controller: phoneController,
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          label: 'Email Address (optional)',
                          controller: emailController,
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          label: 'GCash Number (optional)',
                          controller: gcashController,
                          icon: Icons.account_balance_wallet_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          label: 'Maya Number (optional)',
                          controller: mayaController,
                          icon: Icons.credit_card_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 24),
                        TabbyButton(
                          label: isSubmitting ? 'Saving...' : 'Save Changes',
                          isLoading: isSubmitting,
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  final name = nameController.text.trim();
                                  final phone = phoneController.text.trim();
                                  final email = emailController.text.trim();

                                  if (name.isEmpty) {
                                    ScaffoldMessenger.of(context).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please enter a valid friend name.'),
                                        backgroundColor: TabbyColors.alertRed,
                                      ),
                                    );
                                    return;
                                  }

                                  if (phone.isNotEmpty) {
                                    final cleanDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
                                    if (cleanDigits.length < 10) {
                                      ScaffoldMessenger.of(context).clearSnackBars();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please enter a valid mobile number (min 10 digits).'),
                                          backgroundColor: TabbyColors.alertRed,
                                        ),
                                      );
                                      return;
                                    }
                                  }

                                  if (email.isNotEmpty &&
                                      !RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$').hasMatch(email)) {
                                    ScaffoldMessenger.of(context).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please enter a valid email address.'),
                                        backgroundColor: TabbyColors.alertRed,
                                      ),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSubmitting = true);

                                  ref.read(tabbyProvider.notifier).updateFriend(
                                        id: friend.id,
                                        name: name,
                                        phone: phone.isNotEmpty ? phone : friend.phone,
                                        email: email,
                                        gcashNumber: gcashController.text.trim(),
                                        mayaNumber: mayaController.text.trim(),
                                      );

                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Updated details for $name!'),
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

  // 7d. Remove Friend Confirmation
  void _showRemoveFriendConfirmation(BuildContext context, TabbyUser friend) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.person_remove_rounded, color: TabbyColors.alertRed, size: 22),
              SizedBox(width: 8),
              Text(
                'Remove Friend',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to remove ${friend.displayName} from your friends list?',
            style: const TextStyle(fontSize: 14, color: TabbyColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: TabbyColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(tabbyProvider.notifier).removeFriend(friend.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${friend.displayName} has been removed from your friends list.'),
                    backgroundColor: TabbyColors.brandDarkTeal,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TabbyColors.alertRed,
                foregroundColor: TabbyColors.surfaceWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  // 7e. Create Group Sheet
  void _showCreateGroupSheet(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
    final nameController = TextEditingController();
    final customMemberController = TextEditingController();
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
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Material(
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
                          style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
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
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                        ),
                        const SizedBox(height: 8),
                        if (friends.isEmpty)
                          const Text(
                            'No friends added yet. Add member names below.',
                            style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: friends.map((friend) {
                              final isSelected = selectedFriendIds.contains(friend.id);
                              return FilterChip(
                                label: Text(friend.displayName),
                                selected: isSelected,
                                selectedColor: TabbyColors.brandMintAccent,
                                checkmarkColor: TabbyColors.brandEmerald,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? TabbyColors.brandEmerald : TabbyColors.brandDarkTeal,
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
                        const SizedBox(height: 14),
                        _buildInputField(
                          label: 'Add Extra Member Name (optional)',
                          controller: customMemberController,
                          icon: Icons.person_add_alt_1_rounded,
                        ),
                        const SizedBox(height: 24),
                        TabbyButton(
                          label: isSubmitting ? 'Creating...' : 'Create Group Tab',
                          isLoading: isSubmitting,
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  final groupName = nameController.text.trim();
                                  if (groupName.isEmpty) {
                                    ScaffoldMessenger.of(context).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please enter a group name.'),
                                        backgroundColor: TabbyColors.alertRed,
                                      ),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSubmitting = true);

                                  final memberNames = <String>[];
                                  for (final id in selectedFriendIds) {
                                    final f = friends.where((x) => x.id == id).firstOrNull;
                                    if (f != null) memberNames.add(f.displayName);
                                  }

                                  final custom = customMemberController.text.trim();
                                  if (custom.isNotEmpty) {
                                    memberNames.add(custom);
                                  }

                                  if (memberNames.isEmpty) {
                                    memberNames.add('Barkada Member');
                                  }

                                  ref.read(tabbyProvider.notifier).addGroupTab(
                                        groupName: groupName,
                                        memberNames: memberNames,
                                        memberUserIds: selectedFriendIds.toList(),
                                      );

                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Group "$groupName" created successfully!'),
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

  // 7f. Group Options Sheet
  void _showGroupOptionsSheet(BuildContext context, BilateralTab group) {
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.groupName ?? group.counterpart.displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyColors.brandDarkTeal,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              group.counterpart.phone.isNotEmpty
                                  ? group.counterpart.phone
                                  : 'Group Tab',
                              style: const TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
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
                      child: const Icon(Icons.receipt_long_rounded, color: TabbyColors.brandEmerald, size: 20),
                    ),
                    title: const Text('Open Group Tab', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text('View group balance and expenses', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      context.go('/tabs/${group.id}');
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
                      child: const Icon(Icons.add_circle_outline_rounded, color: TabbyColors.accentBlue, size: 20),
                    ),
                    title: const Text('Log Group Expense', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text('Add a shared bill or split for this group', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      AddExpenseModal.show(context, initialCounterpartId: group.id);
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
                      child: const Icon(Icons.delete_outline_rounded, color: TabbyColors.alertRed, size: 20),
                    ),
                    title: const Text('Delete Group Tab', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: TabbyColors.alertRed)),
                    subtitle: const Text('Remove group tab and associated records', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showRemoveGroupConfirmation(context, group);
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

  // 7g. Remove Group Confirmation Dialog
  void _showRemoveGroupConfirmation(BuildContext context, BilateralTab group) {
    final title = group.groupName ?? group.counterpart.displayName;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: TabbyColors.alertRed, size: 22),
              SizedBox(width: 8),
              Text(
                'Delete Group Tab',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete "$title"? This will remove all associated group records.',
            style: const TextStyle(fontSize: 14, color: TabbyColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: TabbyColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(tabbyProvider.notifier).removeGroupTab(group.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Group "$title" has been deleted.'),
                    backgroundColor: TabbyColors.alertRed,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TabbyColors.alertRed,
                foregroundColor: TabbyColors.surfaceWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Delete'),
            ),
          ],
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              child: const Text('Cancel', style: TextStyle(color: TabbyColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                AppState.isAuthenticated.value = false;
                ref.read(currentUserProvider.notifier).reset();
                ref.read(tabbyProvider.notifier).reset();
                if (context.mounted) context.go('/login');
                unawaited(SupabaseTabbyRepository.instance.signOut());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TabbyColors.alertRed,
                foregroundColor: TabbyColors.surfaceWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          labelStyle: const TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
          prefixIcon: Icon(icon, size: 20, color: TabbyColors.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: TabbyColors.textSecondary),
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
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
          ),
        ),
      ],
    );
  }

  Widget _buildFaqItem({required String question, required String answer, bool initiallyExpanded = false}) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        title: Text(
          question,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              answer,
              style: const TextStyle(fontSize: 12, color: TabbyColors.textSecondary, height: 1.4),
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
        _message = user == null
            ? 'No Tabby account was found for that ID.'
            : null;
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
