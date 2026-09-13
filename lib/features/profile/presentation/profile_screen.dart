import 'package:flutter/material.dart';
import '../../../core/theme/tabby_colors.dart';
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
    final user = MockTabbyRepository.currentUser;

    return Scaffold(
      backgroundColor: TabbyColors.backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Profile & Settings',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.5),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          children: [
            // User Profile Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: TabbyColors.accentAmber.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: TabbyColors.accentAmber, width: 2),
                          ),
                          child: const Center(
                            child: Text(
                              'F',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: TabbyColors.primaryCharcoal,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: TabbyColors.primaryCharcoal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, size: 12, color: TabbyColors.surfaceWhite),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: TabbyColors.primaryCharcoal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.phone,
                            style: const TextStyle(
                              fontSize: 13,
                              color: TabbyColors.secondaryMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            user.email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: TabbyColors.secondaryMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // GCash / Maya Settlement QR Placeholder Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.qr_code_2_rounded, color: TabbyColors.primaryCharcoal),
                            SizedBox(width: 8),
                            Text(
                              'My Payment QR Ph',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: TabbyColors.primaryCharcoal,
                              ),
                            ),
                          ],
                        ),
                        Chip(
                          label: Text('GCash / Maya', style: TextStyle(fontSize: 10)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: TabbyColors.backgroundLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: TabbyColors.borderGray, style: BorderStyle.solid),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined, size: 32, color: TabbyColors.secondaryMuted),
                            const SizedBox(height: 6),
                            const Text(
                              'Upload your GCash or Maya QR code',
                              style: TextStyle(fontSize: 12, color: TabbyColors.textMuted),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('QR upload feature enabled for camera & gallery!')),
                                );
                              },
                              child: const Text('Select from Photos', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tabby Mascot Sheet Preview
            Card(
              child: ExpansionTile(
                leading: const Text('🐱', style: TextStyle(fontSize: 22)),
                title: const Text(
                  'About Tabby Mascot & Moods',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  '9 Emotional States & Turnaround Sheet',
                  style: TextStyle(fontSize: 12, color: TabbyColors.secondaryMuted),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/branding/tabby-mascot-sheet.jpg',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Text('Mascot sheet loading'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '"Keep tabs. Settle up. Para klaro ang usapan."',
                          style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Preferences & Settings List
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Push Notifications & Reminders', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Gentle nudges and settlement confirmations', style: TextStyle(fontSize: 12)),
                    value: _notificationsEnabled,
                    activeColor: TabbyColors.primaryCharcoal,
                    onChanged: (val) => setState(() => _notificationsEnabled = val),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Biometric Security', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Fingerprint / Face Unlock for app entry', style: TextStyle(fontSize: 12)),
                    value: _biometricsEnabled,
                    activeColor: TabbyColors.primaryCharcoal,
                    onChanged: (val) => setState(() => _biometricsEnabled = val),
                  ),
                  const Divider(),
                  const ListTile(
                    leading: Icon(Icons.currency_exchange_rounded, size: 20),
                    title: Text('Currency Precision', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text('Philippine Peso (₱ / PHP) • Integer Centavos (ADR-001)', style: TextStyle(fontSize: 12)),
                    trailing: Text('100¢ = ₱1.00', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.cloud_done_outlined, size: 20, color: TabbyColors.successGreen),
                    title: const Text('Backend & Offline Sync', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Supabase BaaS + Local Drift SQLite', style: TextStyle(fontSize: 12)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: TabbyColors.successLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Online', style: TextStyle(color: TabbyColors.successGreen, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Version & Copyright Footer
            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/branding/tabby-icon.jpg',
                    width: 36,
                    height: 36,
                    errorBuilder: (_, __, ___) => const Text('🐱', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tabby v0.1.0 Phase 1 MVP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: TabbyColors.secondaryMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Built with Flutter, Riverpod, GoRouter & Supabase',
                    style: TextStyle(
                      fontSize: 11,
                      color: TabbyColors.secondaryMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
