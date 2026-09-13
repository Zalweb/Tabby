import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/tabby_providers.dart';
import '../data/mock_tabby_repository.dart';
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
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  ExpenseCategory _selectedCategory = ExpenseCategory.food;
  bool _paidByMe = true;
  bool _isKkbSplit = true;
  DateTime? _selectedDueDate;

  // Preset quick amount chips in pesos
  final List<int> _quickAmounts = [100, 250, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    final friends = MockTabbyRepository.sampleFriends;
    if (widget.initialCounterpartId != null) {
      final match = friends.firstWhere(
        (f) => f.id == widget.initialCounterpartId,
        orElse: () => friends.first,
      );
      _selectedFriendId = match.id;
      _selectedFriendName = match.displayName;
    } else {
      _selectedFriendId = friends.first.id;
      _selectedFriendName = friends.first.displayName;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submitExpense() {
    final centavos = CurrencyFormatter.parseToCentavos(_amountController.text);
    if (centavos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an amount greater than ₱0.00'),
          backgroundColor: TabbyColors.debtRed,
        ),
      );
      return;
    }

    // Check possible duplicate (ADR / Acceptance scenario 7)
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
    ref.read(tabbyProvider.notifier).addExpense(
          counterpartId: _selectedFriendId,
          counterpartName: _selectedFriendName,
          title: _descriptionController.text.trim().isEmpty
              ? _selectedCategory.displayName
              : _descriptionController.text.trim(),
          totalAmountCentavos: centavos,
          category: _selectedCategory,
          paidByMe: _paidByMe,
          isKkbSplit: _isKkbSplit,
          dueDate: _selectedDueDate,
        );

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🐾 Logged ${CurrencyFormatter.formatCentavos(centavos)} with $_selectedFriendName!',
        ),
        backgroundColor: TabbyColors.primaryCharcoal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showDuplicateWarning(int centavos) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Text('⚠️', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('Possible Duplicate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                Navigator.pop(context); // close dialog
                _commitExpense(centavos);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TabbyColors.primaryCharcoal,
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
    final friends = MockTabbyRepository.sampleFriends;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: TabbyColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: TabbyColors.borderGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Quick Log Expense 🐾',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: TabbyColors.primaryCharcoal,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 1. Participant Picker
            const Text(
              'Friend / Barkada',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyColors.secondaryMuted,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: friends.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final f = friends[index];
                  final isSelected = f.id == _selectedFriendId;
                  return ChoiceChip(
                    label: Text(f.displayName),
                    selected: isSelected,
                    selectedColor: TabbyColors.accentAmber,
                    labelStyle: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? TabbyColors.primaryCharcoal : TabbyColors.textMuted,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedFriendId = f.id;
                          _selectedFriendName = f.displayName;
                        });
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // 2. Large Amount Input Keypad Target
            const Text(
              'Total Amount (₱)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyColors.secondaryMuted,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: TabbyColors.backgroundLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: TabbyColors.borderGray, width: 1.5),
              ),
              child: Row(
                children: [
                  const Text(
                    '₱',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: TabbyColors.primaryCharcoal,
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
                        color: TabbyColors.primaryCharcoal,
                        fontFamily: 'Inter',
                      ),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        hintStyle: TextStyle(color: TabbyColors.secondaryMuted),
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
                    label: Text('+₱$amount', style: const TextStyle(fontSize: 11)),
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

            // 3. Category Chips
            const Text(
              'Category',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: TabbyColors.secondaryMuted,
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
                  label: Text('${cat.emoji} ${cat.displayName}'),
                  selected: isSelected,
                  selectedColor: TabbyColors.accentAmber,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? TabbyColors.primaryCharcoal : TabbyColors.textMuted,
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

            // 4. Description Field
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                hintText: 'Description (e.g. Samgyupsal, Milk tea, Taxi)',
                prefixIcon: const Icon(Icons.edit_outlined, size: 18, color: TabbyColors.secondaryMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // 5. Payer Toggle & Split Mode (KKB)
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
                          color: TabbyColors.secondaryMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('You paid', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: false, label: Text('They paid', style: TextStyle(fontSize: 11))),
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
                          color: TabbyColors.secondaryMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('KKB (50/50)', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: false, label: Text('Full', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {_isKkbSplit},
                        onSelectionChanged: (set) {
                          setState(() {
                            _isKkbSplit = set.first;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 6. Optional Due Date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_outlined, size: 18, color: TabbyColors.secondaryMuted),
                    const SizedBox(width: 8),
                    Text(
                      _selectedDueDate == null
                          ? 'Optional Due Date'
                          : 'Due: ${DateFormat('MMM d, yyyy').format(_selectedDueDate!)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: TabbyColors.primaryCharcoal,
                      ),
                    ),
                  ],
                ),
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
                  child: Text(_selectedDueDate == null ? 'Set Date' : 'Change'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Submit Button (<5s entry benchmark)
            TabbyButton(
              label: 'Save Tab 🐾',
              variant: TabbyButtonVariant.primary,
              onPressed: _submitExpense,
            ),
          ],
        ),
      ),
    );
  }
}
