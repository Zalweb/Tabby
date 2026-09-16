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
typedef FriendRequestSubmitter = Future<FriendRequest?> Function(
    String friendCode);

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
 …31263 tokens truncated…dIds = <String>{};
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

