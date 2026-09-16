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

  static Future<void> show(BuildContext context, {String? initialCounterpartId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddExpenseModal(initialCounterpartId: initialCounterpartId),
    );
  }

  @override
  ConsumerState<AddExpenseModal> createState() => _AddExpenseModalState();
}

class _AddExpenseModalState extends ConsumerState<AddExpenseModal> {
  late String _selectedFriendId;
  late String _selectedFriendName;
  bool _selectedFriendIsConnected = false;
  final TextEditingController _friendNameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  ExpenseCategory _selectedCategory = ExpenseCategory.food;
  bool _paidByMe = true;
  bool _isEqualSplit = true;
  DateTime? _selectedDueDate;
  String? _receiptUrl;
  bool _isSubmitting = false;

  // Preset quick amount chips in pesos
  final List<int> _quickAmounts = [100, 250, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    if (widget.initialCounterpartId != null) {
      final tabs = ref.read(tabbyProvider).tabs;
      final match = tabs.where((t) => t.id == widget.initialCounterpartId || t.counterpart.id == widget.initialCounterpartId).firstOrNull;
      if (match != null) {
        _selectedFriendId = match.isGroupTab ? match.id : match.counterpart.id;
        _selectedFriendName = match.isGroupTab ? (match.groupName ?? match.counterpart.displayName) : match.counterpart.displayName;
        _selectedFriendIsConnected = !match.isGroupTab && _isConnectedFriend(match.counterpart);
        _friendNameController.text = _selectedFriendName;
      } else {
        _selectedFriendId = widget.initialCounterpartId!;
        _selectedFriendName = widget.initialCounterpartId!;
        _friendNameController.text = widget.initialCounterpartId!;
      }
    } else {
      final friends = ref.read(friendsProvider);
      if (friends.isNotEmpty) {
        _selectedFriendId = friends.first.id;
        _selectedFriendName = friends.first.displayName;
        _selectedFriendIsConnected = _isConnectedFriend(friends.first);
        _friendNameController.text = friends.first.displayName;
      } else {
        _selectedFriendId = '';
        _selectedFriendName = '';
        _friendNameController.text = '';
      }
    }
  }

  @override
  void dispose() {
    _friendNameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submitExpense() {
    if (_isSubmitting) return;

    final name = _friendNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a friend or group name'),
          backgroundColor: TabbyColors.alertRed,
        ),
      );
      return;
    }

    _selectedFriendName = name;
    final friends = ref.read(friendsProvider);
    final groups = ref.read(groupsProvider);
    final friendMatch = friends.where((f) => f.displayName.toLowerCase() == name.toLowerCase()).firstOrNull;
    final groupMatch = groups.where((g) => (g.groupName ?? g.counterpart.displayName).toLowerCase() == name.toLowerCase()).firstOrNull;

    if (friendMatch != null) {
      _selectedFriendId = friendMatch.id;
      _selectedFriendIsConnected = _isConnectedFriend(friendMatch);
    } else if (groupMatch != null) {
      _selectedFriendId = groupMatch.id;
      _selectedFriendIsConnected = false;
    } else if (_selectedFriendId.isNotEmpty && _selectedFriendName.toLowerCase() == name.toLowerCase()) {
      // Retain pre-selected or pre-filled valid ID (e.g. from bilateral tab)
    } else {
      _selectedFriendId = 'user-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}';
      _selectedFriendIsConnected = false;
    }

    final centavos = CurrencyFormatter.parseToCentavos(_amountController.text);
    if (centavos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an amount greater than PHP 0.00'),
          backgroundColor: TabbyColors.alertRed,
        ),
      );
      return;
    }

    // Check possible duplicate
    final existingTabs = ref.read(tabbyProvider).tabs;
    final matchingTab = existingTabs.where((t) => t.id == _selectedFriendId || t.counterpart.id == _selectedFriendId).firstOrNull;
    final isPossibleDuplicate = matchingTab?.entries.any(
          (e) =>
              e.totalAmountCentavos == centavos &&
              DateTime.now().difference(e.date).inHours < 24,
        ) ??
        false;

    if (isPossibleDuplicate) {
      _showDuplicateWarning(centavos);
      return;
    }

    _commitExpense(centavos);
  }

  void _commitExpense(int centavos) {
    if (_isSubmitting) return;
    if (mounted) {
      setState(() => _isSubmitting = true);
    }
    ref.read(tabbyProvider.notifier).addExpense(
          counterpartId: _selectedFriendId,
          counterpartName: _selectedFriendName,
          title: _descriptionController.text.trim().isEmpty
              ? _selectedCategory.displayName
              : _descriptionController.text.trim(),
          totalAmountCentavos: centavos,
          category: _selectedCategory,
          paidByMe: _paidByMe,
          isEqualSplit: _isEqualSplit,
          isConnectedFriend: _selectedFriendIsConnected,
          dueDate: _selectedDueDate,
          receiptUrl: _receiptUrl,
        );

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Logged ${CurrencyFormatter.formatCentavos(centavos)} with $_selectedFriendName!',
        ),
        backgroundColor: TabbyColors.brandEmerald,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showDuplicateWarning(int centavos) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: TabbyColors.pendingAmber, size: 24),
              SizedBox(width: 8),
              Text('Possible Duplicate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Text(
            'You logged a similar ${CurrencyFormatter.formatCentavos(centavos)} expense with $_selectedFriendName today. Are you sure you want to log it again?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _commitExpense(centavos);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TabbyColors.brandEmerald,
                foregroundColor: TabbyColors.surfaceWhite,
              ),
              child: const Text('Create Anyway'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(groupsProvider);

    final allParticipants = [
      ...friends.map((f) => (
            id: f.id,
            name: f.displayName,
            isGroup: false,
            isConnected: _isConnectedFriend(f),
          )),
      ...groups.map((g) => (
            id: g.id,
            name: g.groupName ?? g.counterpart.displayName,
            isGroup: true,
            isConnected: false,
          )),
    ];

    return Container(
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
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
            const SizedBox(height: 14),

            // Header (Figma add_expense_7035_3877)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Quick Log Expense',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: TabbyColors.brandDarkTeal,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22, color: TabbyColors.brandDarkTeal),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 1. Participant Input (Friend / Group)
            const Text(
              'Friend or Group Name',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: TabbyColors.brandMintAccent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: TextField(
                controller: _friendNameController,
                onChanged: (val) {
                  setState(() {
                    _selectedFriendName = val;
                    final match = friends.where((f) => f.displayName.toLowerCase() == val.trim().toLowerCase()).firstOrNull;
                    final groupMatch = groups.where((g) => (g.groupName ?? g.counterpart.displayName).toLowerCase() == val.trim().toLowerCase()).firstOrNull;
                    if (match != null) {
                      _selectedFriendId = match.id;
                      _selectedFriendIsConnected = _isConnectedFriend(match);
                    } else if (groupMatch != null) {
                      _selectedFriendId = groupMatch.id;
                      _selectedFriendIsConnected = false;
                    } else {
                      _selectedFriendId = 'user-${val.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}';
                      _selectedFriendIsConnected = false;
                    }
                  });
                },
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TabbyColors.brandDarkTeal,
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter name (e.g. Alex, Maria, Weekend Group)',
                  hintStyle: TextStyle(color: TabbyColors.textSecondary),
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 18, color: TabbyColors.textSecondary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                  filled: false,
                ),
              ),
            ),
            if (allParticipants.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 66,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: allParticipants.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final p = allParticipants[index];
                    final isSelected = p.id == _selectedFriendId ||
                        p.name.toLowerCase() == _friendNameController.text.trim().toLowerCase();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChoiceChip(
                          avatar: p.isGroup
                              ? const Icon(Icons.group_rounded, size: 14, color: TabbyColors.brandDarkTeal)
                              : null,
                          label: Text(p.name),
                          selected: isSelected,
                          selectedColor: TabbyColors.brandEmerald,
                          labelStyle: TextStyle(
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? TabbyColors.surfaceWhite : TabbyColors.brandDarkTeal,
                            fontSize: 12,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedFriendId = p.id;
                                _selectedFriendName = p.name;
                                _selectedFriendIsConnected = p.isConnected;
                                _friendNameController.text = p.name;
                              });
                            }
                          },
                        ),
                        if (!p.isGroup)
                          Text(
                            p.isConnected ? 'Connected' : 'Saved contact',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: TabbyColors.textSecondary,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 2. Large Amount Input Container (Figma Soft Mint Pill)
            const Text(
              'Amount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyColors.textSecondary,
                letterSpacing: 0.2,
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
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: TabbyColors.brandDarkTeal,
                        fontFamily: 'Inter',
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

            // Quick Amount Presets
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickAmounts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final amount = _quickAmounts[index];
                  return ActionChip(
                    label: Text('+₱$amount', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: TabbyColors.brandDarkTeal)),
                    backgroundColor: const Color(0xFFE8F8EE),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      final current = CurrencyFormatter.parseToCentavos(_amountController.text);
                      final newAmount = current + (amount * 100);
                      _amountController.text = (newAmount / 100).toStringAsFixed(2);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // 3. Category Chips with Material Icons (NO EMOJIS)
            const Text(
              'Category',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ExpenseCategory.values.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  avatar: Icon(cat.icon, size: 16, color: isSelected ? TabbyColors.surfaceWhite : TabbyColors.brandDarkTeal),
                  label: Text(cat.displayName),
                  selected: isSelected,
                  selectedColor: TabbyColors.brandEmerald,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? TabbyColors.surfaceWhite : TabbyColors.brandDarkTeal,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedCategory = cat;
                      });
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 4. Description Field (Figma Expense Title)
            const Text(
              'Expense Title',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: TabbyColors.brandMintAccent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: TextField(
                controller: _descriptionController,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TabbyColors.brandDarkTeal,
                ),
                decoration: const InputDecoration(
                  hintText: 'Dinner, Grocery run, Taxi fare',
                  hintStyle: TextStyle(color: TabbyColors.textSecondary),
                  prefixIcon: Icon(Icons.edit_outlined, size: 18, color: TabbyColors.textSecondary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. Message / Notes Field (Figma "Enter Message" node 7035:3877)
            const Text(
              'Enter Message',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: TabbyColors.brandMintAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _messageController,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TabbyColors.brandDarkTeal,
                ),
                decoration: const InputDecoration(
                  hintText: 'Enter Message or notes...',
                  hintStyle: TextStyle(color: TabbyColors.textSecondary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 6. Payer Toggle & Split Mode
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: TabbyColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('You paid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                          ButtonSegment(value: false, label: Text('They paid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                        ],
                        selected: {_paidByMe},
                        onSelectionChanged: (set) {
                          setState(() {
                            _paidByMe = set.first;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Split Mode',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: TabbyColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('50/50 Split', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                          ButtonSegment(value: false, label: Text('Full Share', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                        ],
                        selected: {_isEqualSplit},
                        onSelectionChanged: (Set<bool> set) {
                          setState(() {
                            _isEqualSplit = set.first;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 7. Due Date (Figma calendar input)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 20, color: TabbyColors.brandDarkTeal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedDueDate == null
                              ? 'Optional Due Date'
                              : 'Due: ${DateFormat('MMMM d, yyyy').format(_selectedDueDate!)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
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
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 3)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDueDate = picked;
                      });
                    }
                  },
                  child: Text(
                    _selectedDueDate == null ? 'Set Date' : 'Change',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: TabbyColors.brandEmerald),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 8. Optional Receipt Attachment
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 20, color: TabbyColors.brandDarkTeal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _receiptUrl == null
                              ? 'Attach Receipt / Bill Photo'
                              : 'Receipt: Attached',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _receiptUrl == null ? TabbyColors.brandDarkTeal : TabbyColors.brandEmerald,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_receiptUrl == null) {
                        _receiptUrl = 'receipt_${DateTime.now().millisecondsSinceEpoch}.png';
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Receipt image attached.'),
                            backgroundColor: TabbyColors.brandEmerald,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      } else {
                        _receiptUrl = null;
                      }
                    });
                  },
                  child: Text(
                    _receiptUrl == null ? 'Attach' : 'Remove',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _receiptUrl == null ? TabbyColors.brandEmerald : TabbyColors.alertRed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Submit Button
            TabbyButton(
              label: 'Save Tab',
              variant: TabbyButtonVariant.primary,
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submitExpense,
            ),
          ],
        ),
      ),
    );
  }

  bool _isConnectedFriend(TabbyUser friend) =>
      friend.friendCode?.trim().isNotEmpty == true;
}
