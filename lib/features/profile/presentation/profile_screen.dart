import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/config/app_state.dart';
import '../../tabs/data/mock_tabby_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = true;
  bool _biometricsEnabled = true;

  @override
  Widget build(BuildContext context) {
    const user = MockTabbyRepository.currentUser;

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
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      size: 22,
                      color: TabbyColors.brandDarkTeal,
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
                          Stack(
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
                                      child: Text(
                                        user.displayName.substring(0, 1).toUpperCase(),
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
                                  child: const Icon(Icons.camera_alt_rounded, size: 14, color: TabbyColors.surfaceWhite),
                                ),
                              ),
                            ],
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
                          const Text(
                            'ID: 25030024',
                            style: TextStyle(
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
                                      child: const Icon(Icons.qr_code_2_rounded, color: TabbyColors.brandEmerald, size: 22),
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
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                            decoration: BoxDecoration(
                              color: TabbyColors.brandMintAccent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(Icons.add_a_photo_outlined, size: 28, color: TabbyColors.brandDarkTeal),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Upload your GCash or Maya QR Ph code',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TabbyColors.brandDarkTeal),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  TextButton(
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('QR upload feature ready for camera and gallery!')),
                                      );
                                    },
                                    child: const Text('Select from Photos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TabbyColors.brandEmerald)),
                                  ),
                                ],
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
                            onTap: () {},
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            secondary: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: TabbyColors.iconBgMint,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.security_rounded, color: TabbyColors.brandEmerald, size: 20),
                            ),
                            title: const Text('Security', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal)),
                            subtitle: const Text('Biometric security and fingerprint unlock', style: TextStyle(fontSize: 11, color: TabbyColors.textSecondary)),
                            value: _biometricsEnabled,
                            activeThumbColor: TabbyColors.brandEmerald,
                            onChanged: (val) => setState(() => _biometricsEnabled = val),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            secondary: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: TabbyColors.iconBgBlue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.settings_rounded, color: TabbyColors.accentLightBlue, size: 20),
                            ),
                            title: const Text('Settings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal)),
                            subtitle: const Text('Push notifications and reminders', style: TextStyle(fontSize: 11, color: TabbyColors.textSecondary)),
                            value: _notificationsEnabled,
                            activeThumbColor: TabbyColors.brandEmerald,
                            onChanged: (val) => setState(() => _notificationsEnabled = val),
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
                              child: const Icon(Icons.currency_exchange_rounded, color: TabbyColors.brandEmerald, size: 20),
                            ),
                            title: const Text('Currency Precision', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal)),
                            subtitle: const Text('Philippine Peso (PHP) • Integer Centavos (ADR-001)', style: TextStyle(fontSize: 11, color: TabbyColors.textSecondary)),
                            trailing: const Text('100¢ = ₱1.00', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: TabbyColors.brandEmerald)),
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
                              child: const Icon(Icons.cloud_done_rounded, color: TabbyColors.accentLightBlue, size: 20),
                            ),
                            title: const Text('Backend & Offline Sync', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal)),
                            subtitle: const Text('Supabase BaaS and Drift local cache', style: TextStyle(fontSize: 11, color: TabbyColors.textSecondary)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: TabbyColors.brandMintAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Online', style: TextStyle(color: TabbyColors.brandEmerald, fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const Divider(height: 1),
                          _buildProfileMenuItem(
                            icon: Icons.headset_mic_rounded,
                            iconBg: TabbyColors.iconBgMint,
                            iconColor: TabbyColors.brandEmerald,
                            title: 'Help Center',
                            subtitle: 'Customer support and FAQ',
                            onTap: () {},
                          ),
                          const Divider(height: 1),
                          _buildProfileMenuItem(
                            icon: Icons.logout_rounded,
                            iconBg: const Color(0xFFFEE2E2),
                            iconColor: TabbyColors.alertRed,
                            title: 'Logout',
                            subtitle: 'Sign out of current account',
                            onTap: () {
                              AppState.isAuthenticated.value = false;
                              context.go('/login');
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Friends List Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        Text(
                          '${MockTabbyRepository.sampleFriends.length} friends',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TabbyColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
                        children: MockTabbyRepository.sampleFriends.map((friend) {
                          return Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: TabbyColors.iconBgBlue,
                                  child: Text(
                                    friend.displayName.substring(0, 1).toUpperCase(),
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
                                  friend.phone,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: TabbyColors.textSecondary,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: TabbyColors.textSecondary,
                                  size: 20,
                                ),
                                onTap: () {
                                  // Navigate to the bilateral tab for this friend
                                  // Mock tab IDs follow the convention: tab-{friendId segment}
                                  final friendKey = friend.id.replaceFirst('user-', '');
                                  context.go('/tabs/tab-$friendKey');
                                },
                              ),
                              if (friend != MockTabbyRepository.sampleFriends.last)
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
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: TabbyColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right_rounded, color: TabbyColors.textSecondary, size: 20),
      onTap: onTap,
    );
  }
}
