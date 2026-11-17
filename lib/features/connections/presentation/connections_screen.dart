import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/theme/motion_preferences.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../application/connection_preferences.dart';
import 'private_nickname_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../payment_methods/presentation/friend_receiving_methods_sheet.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart';
import '../../tabs/domain/m2_capabilities.dart';
import '../../tabs/presentation/contact_claim_screen.dart';

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  final _searchController = TextEditingController();
  bool _showArchived = false;
  int _selectedTab = 0; // 0: Friends, 1: Groups, 2: Requests
  final _requestUpdates = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(connectionPreferencesProvider);
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(groupsProvider);
    final requests = ref
        .watch(tabbyProvider)
        .friendRequests
        .where((r) => r.isIncoming && r.status == FriendRequestStatus.pending)
        .toList();

    final query = _searchController.text.trim().toLowerCase();
    final filteredFriends = friends
        .where(
          (f) =>
              query.isEmpty ||
              f.displayName.toLowerCase().contains(query) ||
              (preferences.nicknames[f.id]?.toLowerCase().contains(query) ??
                  false),
        )
        .toList();
    final filteredGroups = groups
        .where(
          (g) =>
              preferences.archived.contains(g.id) == _showArchived &&
              (query.isEmpty ||
                  (g.groupName ?? g.counterpart.displayName)
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();

    return Scaffold(
      backgroundColor: TabbyPalette.of(context).canvas,
      appBar: AppBar(
        backgroundColor: TabbyPalette.of(context).canvas,
        foregroundColor: TabbyPalette.of(context).text,
        title: const Text('Connections'),
        actions: [
          if (M2Capabilities.contactClaiming)
            IconButton(
              tooltip: 'Contact claims',
              icon: const Icon(Icons.how_to_reg),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ContactClaimInbox(
                    queue: ref.read(tabbyProvider.notifier).m2Commands,
                  ),
                ),
              ),
            ),
        ],
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/profile'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: Material(
        color: TabbyPalette.of(context).canvas,
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
                          label: requests.isNotEmpty
                              ? 'Requests (${requests.length})'
                              : 'Requests',
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
            if (preferences.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(child: Text(preferences.error!)),
                    TextButton(
                      onPressed: preferences.busy
                          ? null
                          : ref
                                .read(connectionPreferencesProvider.notifier)
                                .reload,
                      child: const Text('Retry connections'),
                    ),
                  ],
                ),
              ),
            if (_selectedTab == 1)
              SwitchListTile(
                title: const Text('Show archived connections'),
                value: _showArchived,
                onChanged: (value) => setState(() => _showArchived = value),
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
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 18,
                        color: TabbyColors.surfaceWhite,
                      ),
                      onPressed: () => _showAddFriend(context),
                    )
                  : _selectedTab == 1
                  ? TabbyButton(
                      label: 'Create a Group',
                      icon: const Icon(
                        Icons.group_add_rounded,
                        size: 18,
                        color: TabbyColors.surfaceWhite,
                      ),
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
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No friends added yet',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TabbyPalette.of(context).text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Connect with friends using their shareable Tabby ID.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: TabbyPalette.of(context).secondaryText,
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
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              _showArchived ? 'No archived connections.' : 'No groups yet. Create a group tab for barkada dinners, trips, or roommate expenses.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyPalette.of(context).secondaryText),
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
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              'No pending friend requests.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyPalette.of(context).secondaryText),
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
              : request.otherUser.displayName
                    .trim()
                    .substring(0, 1)
                    .toUpperCase();
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: TabbyPalette.of(context).accentTint,
                foregroundColor: TabbyPalette.of(context).link,
                child: Text(
                  initial,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              title: Text(
                request.otherUser.displayName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Wants to connect a shared tab with you.'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_requestUpdates.contains(request.id)) ...[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Updating friend request',
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    tooltip: 'Decline request',
                    icon: Icon(
                      Icons.close_rounded,
                      color: TabbyPalette.of(context).secondaryText,
                    ),
                    onPressed: _requestUpdates.contains(request.id)
                        ? null
                        : () => _respondToRequest(request.id, accept: false),
                  ),
                  IconButton(
                    tooltip: 'Accept request',
                    icon: Icon(
                      Icons.check_rounded,
                      color: TabbyPalette.of(context).link,
                    ),
                    onPressed: _requestUpdates.contains(request.id)
                        ? null
                        : () => _respondToRequest(request.id, accept: true),
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
          color: selected
              ? TabbyColors.brandAmber
              : TabbyPalette.of(context).soft,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? TabbyColors.brandInk
                : (selected
                      ? TabbyPalette.of(context).text
                      : TabbyPalette.of(context).text),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _friendTile(TabbyUser friend) {
    final label =
        ref.watch(connectionPreferencesProvider).nicknames[friend.id] ??
        friend.displayName;
    final initial = label.trim().isEmpty
        ? '?'
        : label.trim().substring(0, 1).toUpperCase();
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: TabbyPalette.of(context).soft,
          foregroundColor: TabbyPalette.of(context).link,
          child: Text(
            initial,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          friend.friendCode ??
              (friend.phone.isNotEmpty ? friend.phone : 'Connected'),
        ),
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
        leading: CircleAvatar(
          backgroundColor: TabbyPalette.of(context).soft,
          child: Icon(
            Icons.groups_rounded,
            color: TabbyPalette.of(context).link,
            size: 20,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
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

  Future<void> _respondToRequest(
    String friendshipId, {
    required bool accept,
  }) async {
    if (_requestUpdates.contains(friendshipId)) return;
    final session = SupabaseConfig.captureSession();
    setState(() => _requestUpdates.add(friendshipId));
    try {
      final success = await ref
          .read(tabbyProvider.notifier)
          .respondToFriendRequest(friendshipId: friendshipId, accept: accept);
      if (!mounted || !SupabaseConfig.isCurrentSession(session)) return;
      TabbyFeedback.of(context).showSnackBar(
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
    } finally {
      if (mounted) setState(() => _requestUpdates.remove(friendshipId));
    }
  }

  Future<void> _showAddFriend(BuildContext context) async {
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

  void _showFriendOptions(TabbyUser friend) {
    showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ConnectionModalScope(
        child: Material(
          color: TabbyPalette.of(context).surface,
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
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyPalette.of(context).text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              friend.friendCode ?? 'Connected',
                              style: TextStyle(
                                fontSize: 12,
                                color: TabbyPalette.of(context).secondaryText,
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
                  leading: Icon(
                    Icons.receipt_long_rounded,
                    color: TabbyPalette.of(context).link,
                  ),
                  title: const Text(
                    'Open shared tab',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('/tabs/${friend.id}');
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.qr_code_rounded,
                    color: TabbyPalette.of(context).link,
                  ),
                  title: const Text('View receiving methods'),
                  subtitle: const Text(
                    'Wallet QR and account details shared with you',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    FriendReceivingMethodsSheet.show(
                      context,
                      userId: friend.id,
                      displayName: friend.displayName,
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.edit_outlined,
                    color: TabbyPalette.of(context).link,
                  ),
                  title: const Text(
                    'Private nickname',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('A label only you see in Connections'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showEditFriendDetails(friend);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.person_remove_outlined,
                    color: TabbyPalette.of(context).errorText,
                  ),
                  title: Text(
                    'Remove Friend',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: TabbyPalette.of(context).errorText,
                    ),
                  ),
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
      ),
    );
  }

  void _showEditFriendDetails(TabbyUser friend) {
    showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => PrivateNicknameSheet(friend: friend),
    );
  }

  void _showRemoveFriendConfirmation(TabbyUser friend) {
    final preferences = ref.read(connectionPreferencesProvider.notifier);
    _confirmConnectionChange(
      title: 'Remove Friend',
      message:
          'Remove ${friend.displayName} from your friends list? Your shared ledger and outstanding balances stay available.',
      label: 'Remove',
      apply: () => ref
          .read(tabbyProvider.notifier)
          .removeFriend(
            friend.id,
            persist: () => preferences.change('unfriend', friend.id),
          ),
      success: '${friend.displayName} has been removed from your friends list.',
    );
  }

  void _showGroupOptions(BilateralTab group) {
    final title = group.groupName ?? group.counterpart.displayName;
    showTabbyBottomSheet<void>(
      sheetAnimationStyle: TabbyMotion.style(context),
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ConnectionModalScope(
        child: Material(
          color: TabbyPalette.of(context).surface,
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
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: TabbyPalette.of(context).text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              group.counterpart.phone.isNotEmpty
                                  ? group.counterpart.phone
                                  : 'Group Tab',
                              style: TextStyle(
                                fontSize: 12,
                                color: TabbyPalette.of(context).secondaryText,
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
                  leading: Icon(
                    Icons.receipt_long_rounded,
                    color: TabbyPalette.of(context).link,
                  ),
                  title: const Text(
                    'Open Group Ledger',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('/tabs/${group.id}');
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.archive_outlined,
                    color: TabbyPalette.of(context).link,
                  ),
                  title: Text(
                    ref
                            .read(connectionPreferencesProvider)
                            .archived
                            .contains(group.id)
                        ? 'Restore connection'
                        : 'Archive connection',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: TabbyPalette.of(context).text,
                    ),
                  ),
                  subtitle: const Text(
                    'Changes only your Connections list. The ledger stays available.',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showRemoveGroupConfirmation(group);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRemoveGroupConfirmation(BilateralTab group) {
    final preferences = ref.read(connectionPreferencesProvider.notifier);
    final archived = preferences.snapshot.archived.contains(group.id);
    final title = group.groupName ?? group.counterpart.displayName;
    _confirmConnectionChange(
      title: archived ? 'Restore connection' : 'Archive connection',
      message: archived
          ? 'Show "$title" in your active Connections list again?'
          : 'Archive "$title" in your Connections list? Your shared ledger, balances and reminders stay available.',
      label: archived ? 'Restore' : 'Archive',
      apply: () =>
          preferences.change(archived ? 'restore' : 'archive', group.id),
      success: archived ? 'Connection restored.' : 'Connection archived. You can restore it from archived connections.',
    );
  }

  void _confirmConnectionChange({
    required String title,
    required String message,
    required String label,
    required Future<bool> Function() apply,
    required String success,
  }) {
    var busy = false;
    String? error;
    showDialog<void>(
      animationStyle: TabbyMotion.style(context),
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ConnectionModalScope(
        child: StatefulBuilder(
          builder: (dialogContext, update) => PopScope(
            canPop: !busy,
            child: AlertDialog(
              scrollable: true,
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(message), if (error != null) Text(error!)],
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          update(() {
                            busy = true;
                            error = null;
                          });
                          var saved = false;
                          try {
                            saved = await apply();
                          } catch (_) {}
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          if (!saved) {
                            update(() {
                              busy = false;
                              error =
                                  'Change could not be verified. Please retry.';
                            });
                            return;
                          }
                          Navigator.pop(dialogContext);
                          TabbyFeedback.of(context)
                              .showSnackBar(SnackBar(content: Text(success)));
                        },
                  child: Text(busy ? 'Saving...' : label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateGroup(BuildContext context) {
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
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText:
                                'Group Name (e.g. Barkada Dinner, Room 302)',
                            prefixIcon: Icon(Icons.groups_rounded),
                          ),
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
}

class _ConnectionModalScope extends ConsumerStatefulWidget {
  const _ConnectionModalScope({required this.child});
  final Widget child;
  @override
  ConsumerState<_ConnectionModalScope> createState() =>
      _ConnectionModalScopeState();
}

class _ConnectionModalScopeState extends ConsumerState<_ConnectionModalScope> {
  late final SessionStamp _stamp;
  late final String _owner;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _stamp = SupabaseConfig.captureSession();
    _owner = ref.read(currentUserProvider).id;
    SupabaseConfig.sessionRevision.addListener(_close);
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        Navigator.pop(context);
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    SupabaseConfig.sessionRevision.removeListener(_close);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider.select((user) => user.id), (previous, next) {
      if (next != _owner) _close();
    });
    if (!SupabaseConfig.isCurrentSession(_stamp)) _close();
    return widget.child;
  }
}
