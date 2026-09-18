import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/tabby_providers.dart';
import '../domain/models.dart';

class AddExpenseModal extends ConsumerStatefulWidget {
  final String? initialCounterpartId;

  const AddExpenseModal({
    super.key,
    this.initialCounterpartId,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialCounterpartId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddExpenseModal(
        initialCounterpartId: initialCounterpartId,
      ),
    );
  }

  @override
  ConsumerState<AddExpenseModal> createState() => _AddExpenseModalState();
}

class _AddExpenseModalState extends ConsumerState<AddExpenseModal> {
  final TextEditingController _friendSearchController = TextEditingController();
  final TextEditingController _unregisteredNameController =
      TextEditingController();
  final TextEditingController _tabNameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  final Set<String> _selectedFriendIds = <String>{};
  String? _unregisteredName;
  String? _selectedExistingGroupId;
  String? _selectedExistingGroupName;
  int _step = 0;
  ExpenseCategory _selectedCategory = ExpenseCategory.food;
  bool _paidByMe = true;
  bool _isEqualSplit = true;
  DateTime? _selectedDueDate;
  String? _receiptUrl;
  bool _isSubmitting = false;
  bool _hasCreatedTab = false;

  final List<int> _quickAmounts = [100, 250, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    _seedInitialParticipant();
  }

  @override
  void dispose() {
    _friendSearchController.dispose();
    _unregisteredNameController.dispose();
    _tabNameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _seedInitialParticipant() {
    final initialId = widget.initialCounterpartId;
    if (initialId == null || initialId.isEmpty) return;

    final tabs = ref.read(tabbyProvider).tabs;
    final match = tabs
        .where((tab) => tab.id == initialId || tab.counterpart.id == initialId)
        .firstOrNull;
    if (match == null) {
      _unregisteredName = initialId;
      return;
    }

    if (match.isGroupTab) {
      _selectedExistingGroupId = match.id;
      _selectedExistingGroupName =
          match.groupName ?? match.counterpart.displayName;
      _tabNameController.text = _selectedExistingGroupName!;
      return;
    }

    _selectedFriendIds.add(match.counterpart.id);
    _tabNameController.text = match.counterpart.displayName;
  }

  List<TabbyUser> _selectedFriends(List<TabbyUser> friends) {
    return friends
        .where((friend) => _selectedFriendIds.contains(friend.id))
        .toList();
  }

  String? get _participantError {
    if (_selectedExistingGroupId != null) return null;
    if (_selectedFriendIds.isEmpty && _unregisteredName == null) {
      return 'Choose at least one friend or add an unregistered person.';
    }
    if (_unregisteredName != null && _selectedFriendIds.isNotEmpty) {
      return 'Group tabs require registered Tabby friends.';
    }
    return null;
  }

  void _selectFriend(TabbyUser friend, bool selected) {
    setState(() {
      _selectedExistingGroupId = null;
      _selectedExistingGroupName = null;
      if (selected) {
        _selectedFriendIds.add(friend.id);
        _tabNameController.text = _selectedFriendIds.length == 1
            ? friend.displayName
            : _tabNameController.text;
      } else {
        _selectedFriendIds.remove(friend.id);
        if (_selectedFriendIds.isEmpty && _unregisteredName == null) {
          _tabNameController.clear();
        }
      }
    });
  }

  void _addUnregisteredPerson() {
    final name = _unregisteredNameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a name for the unregistered person.');
      return;
    }

    setState(() {
      _selectedExistingGroupId = null;
      _selectedExistingGroupName = null;
      _unregisteredName = name;
      if (_selectedFriendIds.isEmpty) {
        _tabNameController.text = name;
      }
      _unregisteredNameController.clear();
    });
  }

  void _removeUnregisteredPerson() {
    setState(() {
      _unregisteredName = null;
      if (_selectedFriendIds.isEmpty) _tabNameController.clear();
    });
  }

  void _selectExistingGroup(BilateralTab group) {
    setState(() {
      _selectedFriendIds.clear();
      _unregisteredName = null;
      _selectedExistingGroupId = group.id;
      _selectedExistingGroupName =
          group.groupName ?? group.counterpart.displayName;
      _tabNameController.text = _selectedExistingGroupName!;
    });
  }

  void _goToDetails() {
    final error = _participantError;
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _step = 1);
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.pop(context);
    } else if (!_hasCreatedTab) {
      setState(() => _step = 0);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _selectedParticipantName {
    if (_selectedExistingGroupName != null) return _selectedExistingGroupName!;
    if (_unregisteredName != null) return _unregisteredName!;
    final friends = ref.read(friendsProvider);
    return _selectedFriends(friends)
        .map((friend) => friend.displayName)
        .join(', ');
  }

  String get _expenseTitle {
    final description = _descriptionController.text.trim();
    if (description.isNotEmpty) return description;
    final tabName = _tabNameController.text.trim();
    if (tabName.isNotEmpty) return tabName;
    return _selectedCategory.displayName;
  }

  Future<void> _submitCreateTab() async {
    if (_isSubmitting) return;

    final error = _participantError;
    if (error != null) {
      setState(() => _step = 0);
      _showMessage(error);
      return;
    }

    final centavos = CurrencyFormatter.parseToCentavos(_amountController.text);
    if (centavos <= 0) {
      _showMessage('Please enter an amount greater than PHP 0.00');
      return;
    }

    final tabName = _tabNameController.text.trim().isEmpty
        ? _selectedParticipantName
        : _tabNameController.text.trim();
    if (tabName.isEmpty) {
      _showMessage('Please enter a tab name.');
      return;
    }

    final existingTabs = ref.read(tabbyProvider).tabs;
    final targetId = _selectedExistingGroupId ??
        (_selectedFriendIds.length == 1 ? _selectedFriendIds.first : null) ??
        (_unregisteredName == null
            ? null
            : 'user-${_unregisteredName!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}');
    final matchingTab = targetId == null
        ? null
        : existingTabs
            .where(
                (tab) => tab.id == targetId || tab.counterpart.id == targetId)
            .firstOrNull;
    final isPossibleDuplicate = matchingTab?.entries.any(
          (entry) =>
              entry.totalAmountCentavos == centavos &&
              DateTime.now().difference(entry.date).inHours < 24,
        ) ??
        false;

    if (isPossibleDuplicate) {
      _showDuplicateWarning(centavos, tabName);
      return;
    }

    await _commitCreateTab(
      centavos: centavos,
      tabName: tabName,
    );
  }

  void _showDuplicateWarning(int centavos, String tabName) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: TabbyColors.pendingAmber, size: 24),
            SizedBox(width: 8),
            Text('Possible Duplicate',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          'You logged a similar ${CurrencyFormatter.formatCentavos(centavos)} tab with $tabName today. Are you sure you want to create it again?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _commitCreateTab(centavos: centavos, tabName: tabName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: TabbyColors.brandEmerald,
              foregroundColor: TabbyColors.surfaceWhite,
            ),
            child: const Text('Create Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _commitCreateTab({
    required int centavos,
    required String tabName,
  }) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final notifier = ref.read(tabbyProvider.notifier);
    final friends = ref.read(friendsProvider);
    final selectedFriends = _selectedFriends(friends);
    final title = _expenseTitle;

    try {
      if (selectedFriends.length > 1) {
        final groupId = await notifier.createGroupTab(
          groupName: tabName,
          memberNames:
              selectedFriends.map((friend) => friend.displayName).toList(),
          memberUserIds: selectedFriends.map((friend) => friend.id).toList(),
        );
        if (groupId == null || groupId.isEmpty) {
          _showMessage('The group tab could not be created. Please try again.');
          return;
        }

        await notifier.addExpense(
          counterpartId: groupId,
          counterpartName: tabName,
          title: title,
          totalAmountCentavos: centavos,
          category: _selectedCategory,
          paidByMe: _paidByMe,
          isEqualSplit: _isEqualSplit,
          participantCount: selectedFriends.length + 1,
          payerId: _paidByMe ? null : selectedFriends.first.id,
          payerName: _paidByMe ? null : selectedFriends.first.displayName,
          dueDate: _selectedDueDate,
          receiptUrl: _receiptUrl,
        );
      } else if (_selectedExistingGroupId != null) {
        await notifier.addExpense(
          counterpartId: _selectedExistingGroupId!,
          counterpartName: _selectedExistingGroupName ?? tabName,
          title: title,
          totalAmountCentavos: centavos,
          category: _selectedCategory,
          paidByMe: _paidByMe,
          isEqualSplit: _isEqualSplit,
          dueDate: _selectedDueDate,
          receiptUrl: _receiptUrl,
        );
      } else {
        final friend = selectedFriends.firstOrNull;
        final name = friend?.displayName ?? _unregisteredName ?? tabName;
        final id = friend?.id ??
            'user-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}';
        await notifier.addExpense(
          counterpartId: id,
          counterpartName: name,
          title: title,
          totalAmountCentavos: centavos,
          category: _selectedCategory,
          paidByMe: _paidByMe,
          isEqualSplit: _isEqualSplit,
          isConnectedFriend: friend != null,
          dueDate: _selectedDueDate,
          receiptUrl: _receiptUrl,
        );
      }

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _hasCreatedTab = true;
        _step = 2;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage('The tab could not be created. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(groupsProvider);

    return Container(
      constraints: const BoxConstraints(maxHeight: 760),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: TabbyColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: TabbyColors.borderMint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildHeader(),
          const SizedBox(height: 10),
          _buildProgress(),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _step == 0
                    ? _buildAddPeople(friends, groups)
                    : _step == 1
                        ? _buildDetails()
                        : _buildDone(),
              ),
            ),
          ),
          if (_step == 1) ...[
            const SizedBox(height: 10),
            _primaryAction(
              label: 'Create Tab',
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submitCreateTab,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          tooltip: _step == 0 ? 'Close' : 'Back',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
            color: TabbyColors.brandDarkTeal,
          ),
          onPressed: _goBack,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Create Tab',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: TabbyColors.brandDarkTeal,
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (_step == 0)
          Text(
            '${_selectedFriendIds.length + (_unregisteredName == null ? 0 : 1)} selected',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: TabbyColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildProgress() {
    return Row(
      children: [
        _buildProgressStep(1, 'Add People', _step >= 0),
        _buildProgressLine(_step >= 1),
        _buildProgressStep(2, 'Details', _step >= 1),
        _buildProgressLine(_step >= 2),
        _buildProgressStep(3, 'Done', _step >= 2),
      ],
    );
  }

  Widget _buildProgressStep(int number, String label, bool active) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                active ? TabbyColors.brandEmerald : TabbyColors.brandMintAccent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color:
                  active ? TabbyColors.surfaceWhite : TabbyColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color:
                active ? TabbyColors.brandDarkTeal : TabbyColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressLine(bool active) {
    return Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.only(bottom: 18, left: 6, right: 6),
        color: active ? TabbyColors.brandEmerald : TabbyColors.borderMint,
      ),
    );
  }

  Widget _buildAddPeople(List<TabbyUser> friends, List<BilateralTab> groups) {
    final query = _friendSearchController.text.trim().toLowerCase();
    final visibleFriends = friends
        .where((friend) => friend.displayName.toLowerCase().contains(query))
        .toList();

    return Column(
      key: const ValueKey('create-tab-add-people'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add People',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: TabbyColors.brandDarkTeal,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Choose your Tabby friends or add one person by name.',
          style: TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
        ),
        const SizedBox(height: 14),
        _buildSearchField(),
        const SizedBox(height: 16),
        const Text(
          'Friends',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: TabbyColors.brandDarkTeal,
          ),
        ),
        const SizedBox(height: 6),
        if (visibleFriends.isEmpty)
          _buildEmptyPeople('No registered friends found.')
        else
          ...visibleFriends.map(
            (friend) => Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                key: ValueKey('create-tab-friend-${friend.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _selectedFriendIds.contains(friend.id),
                activeColor: TabbyColors.brandEmerald,
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: _buildAvatar(friend.displayName),
                title: Text(
                  friend.displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TabbyColors.brandDarkTeal,
                  ),
                ),
                subtitle: Text(
                  friend.friendCode?.trim().isNotEmpty == true
                      ? 'Connected'
                      : 'Registered friend',
                  style: const TextStyle(
                    fontSize: 10,
                    color: TabbyColors.textSecondary,
                  ),
                ),
                onChanged: (selected) =>
                    _selectFriend(friend, selected ?? false),
              ),
            ),
          ),
        if (groups.isNotEmpty &&
            _selectedFriendIds.isEmpty &&
            _unregisteredName == null) ...[
          const SizedBox(height: 10),
          const Text(
            'Existing Groups',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: TabbyColors.brandDarkTeal,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: groups.map((group) {
              final name = group.groupName ?? group.counterpart.displayName;
              final selected = group.id == _selectedExistingGroupId;
              return ChoiceChip(
                label: Text(name),
                selected: selected,
                selectedColor: TabbyColors.brandEmerald,
                labelStyle: TextStyle(
                  color: selected
                      ? TabbyColors.surfaceWhite
                      : TabbyColors.brandDarkTeal,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => _selectExistingGroup(group),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Unregistered person',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: TabbyColors.brandDarkTeal,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('create-tab-unregistered-name'),
                controller: _unregisteredNameController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addUnregisteredPerson(),
                decoration: _inputDecoration(
                  hintText: 'Add someone not on Tabby',
                  icon: Icons.person_add_alt_1_rounded,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _addUnregisteredPerson,
              style: OutlinedButton.styleFrom(
                foregroundColor: TabbyColors.brandEmerald,
                side: const BorderSide(color: TabbyColors.brandEmerald),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Add Person'),
            ),
          ],
        ),
        if (_unregisteredName != null) ...[
          const SizedBox(height: 8),
          Chip(
            avatar: const Icon(Icons.person_outline_rounded, size: 16),
            label: Text('$_unregisteredName  •  Unregistered'),
            deleteIcon: const Icon(Icons.close_rounded, size: 16),
            onDeleted: _removeUnregisteredPerson,
            backgroundColor: TabbyColors.brandMintAccent,
          ),
        ],
        const SizedBox(height: 18),
        _primaryAction(
          label: 'Next',
          onPressed: _goToDetails,
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      key: const ValueKey('create-tab-friend-search'),
      controller: _friendSearchController,
      onChanged: (_) => setState(() {}),
      decoration: _inputDecoration(
        hintText: 'Search friends...',
        icon: Icons.search_rounded,
      ),
    );
  }

  Widget _buildDetails() {
    final selectedFriends = _selectedFriends(ref.read(friendsProvider));
    final isGroup =
        selectedFriends.length > 1 || _selectedExistingGroupId != null;

    return Column(
      key: const ValueKey('create-tab-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: TabbyColors.brandDarkTeal,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          isGroup
              ? 'Set the name and first expense for this group tab.'
              : 'Add the details for this new tab.',
          style:
              const TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
        ),
        const SizedBox(height: 14),
        _labeledField(
          label: isGroup ? 'Group tab name' : 'Tab name',
          controller: _tabNameController,
          hintText: isGroup ? 'e.g. Barkada Dinner' : 'e.g. Dinner with Alex',
          icon: Icons.label_outline_rounded,
        ),
        const SizedBox(height: 12),
        _labeledField(
          label: 'Expense title',
          controller: _descriptionController,
          hintText: 'Dinner, Grocery run, Taxi fare',
          icon: Icons.edit_outlined,
        ),
        const SizedBox(height: 12),
        const Text(
          'Amount',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TabbyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: TabbyColors.brandMintAccent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Text(
                '₱',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: TabbyColors.brandDarkTeal,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('create-tab-amount'),
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: TabbyColors.brandDarkTeal,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(color: TabbyColors.textSecondary),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    filled: false,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _quickAmounts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final amount = _quickAmounts[index];
              return ActionChip(
                label: Text(
                  '+₱$amount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: TabbyColors.brandDarkTeal,
                  ),
                ),
                backgroundColor: const Color(0xFFE8F8EE),
                padding: EdgeInsets.zero,
                onPressed: () {
                  final current =
                      CurrencyFormatter.parseToCentavos(_amountController.text);
                  final newAmount = current + (amount * 100);
                  _amountController.text = (newAmount / 100).toStringAsFixed(2);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        _buildCategoryPicker(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildSegmentField(
                label: 'Payer',
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('I paid',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('They paid',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  selected: {_paidByMe},
                  onSelectionChanged: (selection) =>
                      setState(() => _paidByMe = selection.first),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSegmentField(
                label: 'Split',
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Equal',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Full share',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  selected: {_isEqualSplit},
                  onSelectionChanged: (selection) =>
                      setState(() => _isEqualSplit = selection.first),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildOptionalRow(
          icon: Icons.event_outlined,
          text: _selectedDueDate == null
              ? 'Optional due date'
              : 'Due: ${DateFormat('MMMM d, yyyy').format(_selectedDueDate!)}',
          action: _selectedDueDate == null ? 'Set date' : 'Change',
          onPressed: _pickDueDate,
        ),
        _buildOptionalRow(
          icon: Icons.receipt_long_outlined,
          text: _receiptUrl == null
              ? 'Attach receipt or bill'
              : 'Receipt attached',
          action: _receiptUrl == null ? 'Attach' : 'Remove',
          onPressed: () {
            setState(() {
              if (_receiptUrl == null) {
                _receiptUrl =
                    'receipt_${DateTime.now().millisecondsSinceEpoch}.png';
                _showMessage('Receipt image attached.');
              } else {
                _receiptUrl = null;
              }
            });
          },
        ),
        const SizedBox(height: 8),
        _labeledField(
          label: 'Notes',
          controller: _messageController,
          hintText: 'Add a note (optional)',
          icon: Icons.notes_outlined,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildCategoryPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Category',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TabbyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: ExpenseCategory.values.map((category) {
            final selected = _selectedCategory == category;
            return ChoiceChip(
              avatar: Icon(
                category.icon,
                size: 15,
                color: selected
                    ? TabbyColors.surfaceWhite
                    : TabbyColors.brandDarkTeal,
              ),
              label: Text(category.displayName),
              selected: selected,
              selectedColor: TabbyColors.brandEmerald,
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? TabbyColors.surfaceWhite
                    : TabbyColors.brandDarkTeal,
              ),
              onSelected: (_) => setState(() => _selectedCategory = category),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      key: const ValueKey('create-tab-done'),
      children: [
        const SizedBox(height: 20),
        Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            color: TabbyColors.brandMintAccent,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 42,
            color: TabbyColors.brandEmerald,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tab created',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: TabbyColors.brandDarkTeal,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your new tab with $_selectedParticipantName is ready.',
          textAlign: TextAlign.center,
          style:
              const TextStyle(fontSize: 13, color: TabbyColors.textSecondary),
        ),
        const SizedBox(height: 24),
        _primaryAction(
          label: 'Done',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildSegmentField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TabbyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildOptionalRow({
    required IconData icon,
    required String text,
    required String action,
    required VoidCallback onPressed,
  }) {
    return Row(
      children: [
        Icon(icon, size: 19, color: TabbyColors.brandDarkTeal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: TabbyColors.brandDarkTeal,
            ),
          ),
        ),
        TextButton(
          onPressed: onPressed,
          child: Text(
            action,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: action == 'Remove'
                  ? TabbyColors.alertRed
                  : TabbyColors.brandEmerald,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDueDate = picked);
    }
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TabbyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: ValueKey(
            hintText == 'e.g. Dinner with Alex' ||
                    hintText == 'e.g. Barkada Dinner'
                ? 'create-tab-tab-name'
                : hintText == 'Dinner, Grocery run, Taxi fare'
                    ? 'create-tab-expense-title'
                    : 'create-tab-notes',
          ),
          controller: controller,
          maxLines: maxLines,
          decoration: _inputDecoration(hintText: hintText, icon: icon),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(
      {required String hintText, required IconData icon}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle:
          const TextStyle(color: TabbyColors.textSecondary, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: TabbyColors.textSecondary),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: true,
      fillColor: TabbyColors.brandMintAccent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _primaryAction({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: TabbyButton(
        label: label,
        variant: TabbyButtonVariant.primary,
        isLoading: isLoading,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildAvatar(String name) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: TabbyColors.brandMintAccent,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: TabbyColors.brandDarkTeal,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEmptyPeople(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TabbyColors.brandMintAccent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, color: TabbyColors.textSecondary),
      ),
    );
  }
}
