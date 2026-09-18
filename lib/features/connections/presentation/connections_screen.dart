import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart';

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  final _searchController = TextEditingController();
  int _selectedTab = 0; // 0: Friends, 1: Groups, 2: Requests

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(groupsProvider);
    final requests = ref
        .watch(tabbyProvider)
        .friendRequests
        .where((r) => r.isIncoming && r.status == FriendRequestStatus.pending)
        .toList();

    final query = _searchController.text.trim().toLowerCase();
    final filteredFriends = friends
        .where((f) =>
            query.isEmpty || f.displayName.toLowerCase().contains(query))
        .toList();
    final filteredGroups = groups
        .where((g) =>
            query.isEmpty ||
            (g.groupName ?? g.counterpart.displayName)
                .toLowerCase()
                .contains(query))
        .toList();

    return Scaffold(
      backgroundColor: TabbyColors.brandEmerald,
      appBar: AppBar(
        backgroundColor: TabbyColors.brandEmerald,
        foregroundColor: TabbyColors.brandDarkTeal,
        title: const Text('Connections'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/profile'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: Material(
        color: TabbyColors.bgCanvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _tabPill(
                          label: 'Friends',
                          selected: _selectedTab == 0,
                          onTap: () => setState(() => _selectedTab = 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _tabPill(
                          label: 'Groups',
                          selected: _selectedTab == 1,
                          onTap: () => setState(() => _selectedTab = 1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _tabPill(
                          label: 'Requests',
                          selected: _selectedTab == 2,
                          onTap: () => setState(() => _selectedTab = 2),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedTab != 2) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: _selectedTab == 0
                            ? 'Search friends...'
                            : 'Search groups...',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _buildTabBody(
                filteredFriends: filteredFriends,
                filteredGroups: filteredGroups,
                requests: requests,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: _selectedTab == 0
                  ? TabbyButton(
                      label: 'Add Friend',
                      icon: const Icon(Icons.person_add_alt_1_rounded,
                          size: 18, color: TabbyColors.surfaceWhite),
                      onPressed: () => _showAddFriend(context),
                    )
                  : _selectedTab == 1
                      ? TabbyButton(
                          label: 'Create a Group',
                          icon: const Icon(Icons.group_add_rounded,
                              size: 18, color: TabbyColors.surfaceWhite),
                          onPressed: () => _showCreateGroup(context),
                        )
                      : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBody({
    required List<TabbyUser> filteredFriends,
    required List<BilateralTab> filteredGroups,
    required List<FriendRequest> requests,
  }) {
    if (_selectedTab == 0) {
      if (filteredFriends.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No friends added yet',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TabbyColors.brandDarkTeal,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Connect with friends using their shareable Tabby ID.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: TabbyColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: filteredFriends.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _friendTile(filteredFriends[index]),
      );
    } else if (_selectedTab == 1) {
      if (filteredGroups.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'No groups yet. Create a group tab for barkada dinners, trips, or roommate expenses.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyColors.textSecondary),
            ),
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: filteredGroups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _groupTile(filteredGroups[index]),
      );
    } else {
      if (requests.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'No pending friend requests.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyColors.textSecondary),
            ),
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final request = requests[index];
          final initial = request.otherUser.displayName.trim().isEmpty
              ? '?'
              : request.otherUser.displayName.trim().substring(0, 1).toUpperCase();
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: TabbyColors.iconBgBlue,
                foregroundColor: TabbyColors.accentLightBlue,
                child: Text(initial,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              title: Text(request.otherUser.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Wants to connect a shared tab with you.'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Decline request',
                    icon: const Icon(Icons.close_rounded,
                        color: TabbyColors.textSecondary),
                    onPressed: () => _respondToRequest(request.id, accept: false),
                  ),
                  IconButton(
                    tooltip: 'Accept request',
                    icon: const Icon(Icons.check_rounded,
                        color: TabbyColors.brandEmerald),
                    onPressed: () => _respondToRequest(request.id, accept: true),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Widget _tabPill({
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color:
              selected ? TabbyColors.brandEmerald : TabbyColors.brandMintAccent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? TabbyColors.surfaceWhite
                : TabbyColors.brandDarkTeal,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _friendTile(TabbyUser friend) {
    final initial = friend.displayName.trim().isEmpty
        ? '?'
        : friend.displayName.trim().substring(0, 1).toUpperCase();
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: TabbyColors.iconBgMint,
          foregroundColor: TabbyColors.brandEmerald,
          child: Text(initial,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        title: Text(friend.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(friend.friendCode ??
            (friend.phone.isNotEmpty ? friend.phone : 'Connected')),
        trailing: IconButton(
          tooltip: 'Friend options',
          onPressed: () => _showFriendOptions(friend),
          icon: const Icon(Icons.more_vert_rounded),
        ),
        onTap: () => context.push('/tabs/${friend.id}'),
      ),
    );
  }

  Widget _groupTile(BilateralTab group) {
    final title = group.groupName ?? group.counterpart.displayName;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: TabbyColors.brandMintAccent,
          child: Icon(Icons.groups_rounded,
              color: TabbyColors.brandEmerald, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          group.counterpart.phone.isNotEmpty
              ? group.counterpart.phone
              : 'Group Tab',
        ),
        trailing: IconButton(
          tooltip: 'Group options',
          onPressed: () => _showGroupOptions(group),
          icon: const Icon(Icons.more_vert_rounded),
        ),
        onTap: () => context.push('/tabs/${group.id}'),
      ),
    );
  }

  Future<void> _respondToRequest(String friendshipId, {required bool accept}) async {
    final success = await ref
        .read(tabbyProvider.notifier)
        .respondToFriendRequest(friendshipId: friendshipId, accept: accept);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _showAddFriend(BuildContext context) async {
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

  void _showFriendOptions(TabbyUser friend) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Material(
        color: TabbyColors.surfaceWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
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
                            friend.friendCode ?? 'Connected',
                            style: const TextStyle(
                              fontSize: 12,
                              color: TabbyColors.textSecondary,
                            ),
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
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.receipt_long_rounded,
                    color: TabbyColors.brandEmerald),
                title: const Text('Open shared tab',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/tabs/${friend.id}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: TabbyColors.brandEmerald),
                title: const Text('Edit Friend Details',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Update name, mobile, or payment numbers'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showEditFriendDetails(friend);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined,
                    color: TabbyColors.alertRed),
                title: const Text('Remove Friend',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: TabbyColors.alertRed)),
                subtitle: const Text('Remove from your friends list'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRemoveFriendConfirmation(friend);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditFriendDetails(TabbyUser friend) {
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
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Friend\'s Full Name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Mobile Number (+63 9XX XXX XXXX)',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email Address (optional)',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: gcashController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'GCash Number (optional)',
                            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: mayaController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Maya Number (optional)',
                            prefixIcon: Icon(Icons.credit_card_outlined),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TabbyButton(
                          label: isSubmitting ? 'Saving...' : 'Save Changes',
                          isLoading: isSubmitting,
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final newName = nameController.text.trim();
                                  if (newName.isEmpty) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                      content:
                                          Text('Please enter friend\'s name.'),
                                      backgroundColor: TabbyColors.alertRed,
                                    ));
                                    return;
                                  }
                                  setModalState(() => isSubmitting = true);
                                  ref.read(tabbyProvider.notifier).updateFriend(
                                        id: friend.id,
                                        name: newName,
                                        phone: phoneController.text.trim(),
                                        email: emailController.text.trim(),
                                        gcashNumber:
                                            gcashController.text.trim(),
                                        mayaNumber: mayaController.text.trim(),
                                      );
                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '$newName details updated.'),
                                      backgroundColor:
                                          TabbyColors.brandEmerald,
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

  void _showRemoveFriendConfirmation(TabbyUser friend) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Friend',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            'Are you sure you want to remove ${friend.displayName} from your friends list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: TabbyColors.alertRed,
              foregroundColor: TabbyColors.surfaceWhite,
            ),
            onPressed: () {
              ref.read(tabbyProvider.notifier).removeFriend(friend.id);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    '${friend.displayName} has been removed from your friends list.'),
                backgroundColor: TabbyColors.alertRed,
              ));
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showGroupOptions(BilateralTab group) {
    final title = group.groupName ?? group.counterpart.displayName;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Material(
        color: TabbyColors.surfaceWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
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
                            style: const TextStyle(
                              fontSize: 12,
                              color: TabbyColors.textSecondary,
                            ),
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
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.receipt_long_rounded,
                    color: TabbyColors.brandEmerald),
                title: const Text('Open Group Ledger',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/tabs/${group.id}');
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: TabbyColors.alertRed),
                title: const Text('Delete Group Tab',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: TabbyColors.alertRed)),
                subtitle: const Text('Remove group tab and associated records'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRemoveGroupConfirmation(group);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRemoveGroupConfirmation(BilateralTab group) {
    final title = group.groupName ?? group.counterpart.displayName;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded,
                color: TabbyColors.alertRed, size: 22),
            SizedBox(width: 8),
            Text('Delete Group Tab',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
            'Are you sure you want to delete "$title"? This will remove all associated group records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: TabbyColors.alertRed,
              foregroundColor: TabbyColors.surfaceWhite,
            ),
            onPressed: () {
              ref.read(tabbyProvider.notifier).removeGroupTab(group.id);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Group "$title" has been deleted.'),
                backgroundColor: TabbyColors.alertRed,
              ));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroup(BuildContext context) {
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
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText:
                                'Group Name (e.g. Barkada Dinner, Room 302)',
                            prefixIcon: Icon(Icons.groups_rounded),
                          ),
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
                                        .showSnackBar(const SnackBar(
                                      content:
                                          Text('Please enter a group name.'),
                                      backgroundColor: TabbyColors.alertRed,
                                    ));
                                    return;
                                  }
                                  if (selectedFriendIds.isEmpty) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                      content: Text(
                                          'Select at least one accepted friend.'),
                                      backgroundColor: TabbyColors.alertRed,
                                    ));
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Group "$groupName" created successfully!'),
                                      backgroundColor:
                                          TabbyColors.brandEmerald,
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
}
