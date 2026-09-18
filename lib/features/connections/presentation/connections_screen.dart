import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart';

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = friends
        .where((friend) =>
            query.isEmpty || friend.displayName.toLowerCase().contains(query))
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
                          selected: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _tabPill(
                          label: 'Requests',
                          selected: false,
                          onTap: () => _showRequests(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search friends...',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _friendTile(filtered[index]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: TabbyButton(
                label: 'Add Friend',
                icon: const Icon(Icons.person_add_alt_1_rounded,
                    size: 18, color: TabbyColors.surfaceWhite),
                onPressed: () => _showAddFriend(context),
              ),
            ),
          ],
        ),
      ),
    );
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
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: selected
                    ? TabbyColors.surfaceWhite
                    : TabbyColors.brandDarkTeal,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
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
          child: Text(initial),
        ),
        title: Text(friend.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(friend.friendCode ?? 'Connected'),
        trailing: IconButton(
          tooltip: 'Friend options',
          onPressed: () => _showFriendOptions(friend),
          icon: const Icon(Icons.more_horiz_rounded),
        ),
        onTap: () => context.push('/tabs/${friend.id}'),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'No accepted friends yet. Add a friend using their Tabby ID.',
          textAlign: TextAlign.center,
          style: TextStyle(color: TabbyColors.textSecondary),
        ),
      ),
    );
  }

  void _showRequests(BuildContext context) {
    final requests = ref
        .read(tabbyProvider)
        .friendRequests
        .where((request) =>
            request.isIncoming && request.status == FriendRequestStatus.pending)
        .toList();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: requests.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: Text('No pending friend requests.'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: requests
                    .map((request) => ListTile(
                          title: Text(request.otherUser.displayName),
                          subtitle: const Text('Pending request'),
                          trailing: IconButton(
                            icon: const Icon(Icons.check_rounded,
                                color: TabbyColors.brandEmerald),
                            onPressed: () async {
                              await ref
                                  .read(tabbyProvider.notifier)
                                  .respondToFriendRequest(
                                    friendshipId: request.id,
                                    accept: true,
                                  );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                          ),
                        ))
                    .toList(),
              ),
      ),
    );
  }

  Future<void> _showAddFriend(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Friend'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Tabby ID'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final request = await ref
                  .read(tabbyProvider.notifier)
                  .sendFriendRequestByCode(controller.text);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(request == null
                      ? 'We could not find that Tabby ID.'
                      : 'Friend request sent.')));
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  void _showFriendOptions(TabbyUser friend) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long_rounded),
              title: const Text('Open shared tab'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/tabs/${friend.id}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: TabbyColors.alertRed),
              title: const Text('Remove Friend'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(tabbyProvider.notifier).removeFriend(friend.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
