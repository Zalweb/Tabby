import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../../shared/widgets/tabby_feedback.dart';
import '../../../core/widgets/account_draft_guard.dart';
import '../../../core/theme/motion_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/receipt_attachment_service.dart';
import '../../../core/services/form_draft_store.dart';
import '../../../core/services/receipt_blob_store.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/theme/tabby_palette.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../shared/widgets/receipt_source_sheet.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/tabby_providers.dart';
import '../domain/models.dart';
import '../domain/ledger_validation.dart';
import '../domain/expense_entry_policy.dart';
import '../data/tabby_local_cache.dart';

class AddExpenseModal extends ConsumerStatefulWidget {
  final String? initialCounterpartId;

  const AddExpenseModal({super.key, this.initialCounterpartId});

  static Future<void> show(
    BuildContext context, {
    String? initialCounterpartId,
  }) {
    return showTabbyFormPage<void>(
      context: context,
      builder: (context) =>
          AddExpenseModal(initialCounterpartId: initialCounterpartId),
    );
  }

  @override
  ConsumerState<AddExpenseModal> createState() => _AddExpenseModalState();
}

class _AddExpenseModalState extends ConsumerState<AddExpenseModal> {
  String _groupCreationOperationId = const Uuid().v4();
  String _newContactId = const Uuid().v4();
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
  String? _selectedGroupPayerId;
  bool _isEqualSplit = true;
  bool _customSplit = false, _createGroup = false, _isChecking = false;
  bool _pendingSave = false;
  bool _needsAttention = false;
  bool _confirmationOpen = false;
  int _selectionRevision = 0;
  String? _existingBilateralId;
  final Map<String, TextEditingController> _customInputs = {};
  bool get _addingToTab =>
      _existingBilateralId != null ||
      _selectedExistingGroupId != null ||
      (_unregisteredName != null &&
          ref
              .read(tabbyProvider)
              .tabs
              .any(
                (tab) =>
                    tab.isTabOnlyParticipant &&
                    tab.counterpart.id == _newContactId,
              ));
  DateTime? _selectedDueDate;
  String? _receiptUrl;
  bool _isSubmitting = false;
  String? _amountError;
  bool _hasCreatedTab = false;
  String _expenseOperationId = const Uuid().v4();
  final _draftStore = const FormDraftStore();
  late final String _owner;
  late final SessionStamp _session;
  String get _purpose => 'expense:${widget.initialCounterpartId ?? 'new'}';
  bool _draftReady = false,
      _restoring = false,
      _allowExit = false,
      _closing = false,
      _attempted = false;
  String? _draftError;
  String _baseline = '', _lastDraft = '';
  Future<void>? _draftWork;
  bool _isPicking = false;
  String? _receiptImage;
  bool get _current =>
      mounted &&
      SupabaseConfig.isCurrentSession(_session) &&
      ref.read(currentUserProvider).id == _owner;
  bool get _dirty => _snapshot().toString() != _baseline;
  Map<String, dynamic> _snapshot() => {
    'operation': _expenseOperationId,
    'group_operation': _groupCreationOperationId,
    'contact': _newContactId,
    'friends': _selectedFriendIds.toList()..sort(),
    'unregistered': _unregisteredName,
    'group': _selectedExistingGroupId,
    'group_name': _selectedExistingGroupName,
    'name': _tabNameController.text,
    'amount': _amountController.text,
    'description': _descriptionController.text,
    'message': _messageController.text,
    'contact_input': _unregisteredNameController.text,
    'step': _step,
    'category': _selectedCategory.name,
    'paid_by_me': _paidByMe,
    'payer': _selectedGroupPayerId,
    'equal': _isEqualSplit,
    'custom': _customSplit,
    'custom_amounts': {
      for (final e in _customInputs.entries) e.key: e.value.text,
    },
    'create_group': _createGroup,
    'existing_bilateral': _existingBilateralId,
    'due': _selectedDueDate?.toIso8601String(),
    'receipt': _receiptUrl,
    'receipt_image': _receiptImage,
    'attempted': _attempted,
  };
  Future<void> _persistDraft() async {
    if (!_draftReady ||
        !_current ||
        _restoring ||
        _hasCreatedTab ||
        _allowExit) {
      return;
    }
    final value = _snapshot(), stamp = _snapshot().toString();
    if (stamp == _lastDraft) {
      await _draftWork;
      return;
    }
    if (!_dirty) return;
    _lastDraft = stamp;
    try {
      await (_draftWork = _draftStore.write(_owner, _purpose, value));
    } catch (_) {
      _lastDraft = '';
      if (_current) {
        super.setState(
          () => _draftError =
              'Draft could not be saved. Keep this form open and retry.',
        );
      }
      rethrow;
    }
  }

  void _changed() {
    if (_draftReady && !_restoring && mounted) super.setState(() {});
    _persistDraft().catchError((Object _) {});
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changed();
  }

  Future<void> _restoreDraft() async {
    try {
      final map = await _draftStore.read(_owner, _purpose);
      if (!_current) return;
      if (map != null) {
        _restoring = true;
        _expenseOperationId = map['operation'] as String;
        _groupCreationOperationId = map['group_operation'] as String;
        _newContactId = map['contact'] as String;
        _selectedFriendIds
          ..clear()
          ..addAll((map['friends'] as List).cast<String>());
        _unregisteredName = map['unregistered'] as String?;
        _selectedExistingGroupId = map['group'] as String?;
        _selectedExistingGroupName = map['group_name'] as String?;
        _tabNameController.text = map['name'] as String;
        _amountController.text = map['amount'] as String;
        _descriptionController.text = map['description'] as String;
        _messageController.text = map['message'] as String;
        _unregisteredNameController.text = map['contact_input'] as String;
        _step = (map['step'] as int).clamp(0, 1);
        _selectedCategory = ExpenseCategory.values.byName(
          map['category'] as String,
        );
        _paidByMe = map['paid_by_me'] as bool;
        _selectedGroupPayerId = map['payer'] as String?;
        _isEqualSplit = map['equal'] as bool;
        _customSplit = map['custom'] == true;
        _createGroup =
            map['create_group'] == true || _selectedFriendIds.length > 1;
        _existingBilateralId = map['existing_bilateral'] as String?;
        for (final e in (map['custom_amounts'] as Map? ?? {}).entries) {
          _customController(e.key as String).text = e.value as String;
        }
        _selectedDueDate = map['due'] == null
            ? null
            : DateTime.parse(map['due'] as String);
        _receiptUrl = map['receipt'] as String?;
        _receiptImage = map['receipt_image'] as String?;
        _attempted = map['attempted'] == true;
        if (_attempted) _step = 1;
      }
      _restoring = false;
      _draftReady = true;
      final recovered = await ReceiptAttachmentService.recovery.restored(
        _owner,
        _purpose,
      );
      if (!_current) return;
      if (recovered != null) await _retainReceipt(recovered);
      super.setState(() {});
    } catch (_) {
      _restoring = false;
      if (_current) {
        super.setState(
          () => _draftError = 'Your draft could not be restored. Retry before entering new details.',
        );
      }
    }
  }

  Future<void> _retainReceipt(XFile file) async {
    if (_receiptImage == file.path && _receiptUrl != null) {
      await ReceiptAttachmentService.recovery.acknowledge(
        _owner,
        _purpose,
        file,
      );
      return;
    }
    final path = await ReceiptBlobStore.save(
      await file.readAsBytes(),
      ownerId: _owner,
    );
    if (!_current) return;
    _receiptUrl = path;
    _receiptImage = file.path;
    await _persistDraft();
    await ReceiptAttachmentService.recovery.acknowledge(_owner, _purpose, file);
  }

  Future<void> _leave() async {
    if (_closing || _isSubmitting || _isPicking || !_current) return;
    if (_step > 0 && !_hasCreatedTab && !_attempted) {
      setState(() => _step = 0);
      return;
    }
    _closing = true;
    try {
      if ((_dirty || !_draftReady) && !_hasCreatedTab) {
        final choice = await showDialog<String>(
          context: context,
          animationStyle: TabbyMotion.style(context),
          builder: (dialog) => AlertDialog(
            scrollable: true,
            title: const Text('Keep this expense draft?'),
            content: Text(
              _attempted
                  ? 'Any expense already queued remains in your tab. Keeping this draft lets you retry the same operation.'
                  : 'Keep the draft to finish later, or discard these unsaved details.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, 'discard'),
                child: const Text('Discard draft'),
              ),
              TextButton(
                onPressed: _draftReady
                    ? () => Navigator.pop(dialog, 'keep')
                    : null,
                child: const Text('Keep draft'),
              ),
            ],
          ),
        );
        if (choice == null || !_current) return;
        if (choice == 'keep') {
          _lastDraft = '';
          await _persistDraft();
        } else {
          await _draftStore.remove(_owner, _purpose);
          await ReceiptAttachmentService.recovery.discard(_owner, _purpose);
        }
      }
      if (!_current || !mounted) return;
      _allowExit = true;
      Navigator.pop(context);
    } catch (_) {
      if (_current) _showMessage('Draft could not be saved. Please retry.');
    } finally {
      _closing = false;
    }
  }

  final List<int> _quickAmounts = [100, 250, 500, 1000, 2000];

  @override
  void initState() {
    super.initState();
    _owner = ref.read(currentUserProvider).id;
    _session = SupabaseConfig.captureSession();
    _seedInitialParticipant();
    _baseline = _snapshot().toString();
    for (final controller in [
      _unregisteredNameController,
      _tabNameController,
      _amountController,
      _descriptionController,
      _messageController,
    ]) {
      controller.addListener(_changed);
    }
    _restoreDraft();
  }

  @override
  void dispose() {
    for (final controller in _customInputs.values) {
      controller.dispose();
    }
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
      // A missing/loading tab ID must never become a new contact identity.
      return;
    }

    if (match.isGroupTab) {
      _selectedExistingGroupId = match.id;
      _selectedExistingGroupName =
          match.groupName ?? match.counterpart.displayName;
      _tabNameController.text = _selectedExistingGroupName!;
      return;
    }

    if (match.isTabOnlyParticipant) {
      _newContactId = match.counterpart.id;
      _unregisteredName = match.counterpart.displayName;
      _tabNameController.text = match.counterpart.displayName;
      return;
    }

    _selectedFriendIds.add(match.counterpart.id);
    _existingBilateralId = match.id;
    _tabNameController.text = match.counterpart.displayName;
  }

  List<TabbyUser> _selectedFriends(List<TabbyUser> friends) {
    final selected = friends
        .where((friend) => _selectedFriendIds.contains(friend.id))
        .toList();
    final existing = ref
        .read(tabbyProvider)
        .tabs
        .where(
          (t) =>
              t.id == _existingBilateralId &&
              !t.isGroupTab &&
              !t.isTabOnlyParticipant,
        )
        .firstOrNull;
    if (existing != null &&
        _selectedFriendIds.contains(existing.counterpart.id) &&
        !selected.any((friend) => friend.id == existing.counterpart.id)) {
      selected.add(existing.counterpart);
    }
    return selected;
  }

  List<TabbyUser> get _groupMembers {
    if (_selectedExistingGroupId != null) {
      return ref
              .read(tabbyProvider)
              .tabs
              .where((t) => t.id == _selectedExistingGroupId)
              .firstOrNull
              ?.members ??
          const [];
    }
    return [
      ref.read(currentUserProvider),
      ..._selectedFriends(ref.read(friendsProvider)),
    ];
  }

  TabbyUser? get _groupPayer {
    final id = _selectedGroupPayerId ?? ref.read(currentUserProvider).id;
    return _groupMembers.where((m) => m.id == id).firstOrNull;
  }

  String? get _participantError {
    if (_selectedExistingGroupId != null) return null;
    if (_selectedFriendIds.isEmpty && _unregisteredName == null) {
      return 'Choose at least one friend or add an unregistered person.';
    }
    if (_unregisteredName != null && _selectedFriendIds.isNotEmpty) {
      return 'Group tabs require registered Tabby friends.';
    }
    if (_createGroup && _selectedFriendIds.length < 2) {
      return 'Choose at least two registered friends for a group tab.';
    }
    return null;
  }

  Future<void> _selectFriend(TabbyUser friend, bool selected) async {
    if (_isChecking || _attempted) return;
    final revision = ++_selectionRevision;
    if (selected && !_createGroup) {
      setState(() => _isChecking = true);
      try {
        final tab = await ref
            .read(tabbyProvider.notifier)
            .inspectSharedTab(friend.id);
        if (!_current || revision != _selectionRevision) return;
        if (tab != null) {
          await _showExistingTab(tab, friend);
          return;
        }
      } catch (_) {
        if (_current) {
          _showMessage(
            'Could not check your shared tab. Check your connection and try again.',
          );
        }
        return;
      } finally {
        if (_current && revision == _selectionRevision) {
          setState(() => _isChecking = false);
        }
      }
    }
    if (!_current) return;
    setState(() {
      _existingBilateralId = null;
      _selectedExistingGroupId = null;
      _selectedExistingGroupName = null;
      if (selected) {
        if (!_createGroup) _selectedFriendIds.clear();
        _unregisteredName = null;
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

  Future<void> _showExistingTab(BilateralTab tab, TabbyUser friend) async {
    final amount = CurrencyFormatter.formatCentavos(
      tab.netBalanceCentavos.abs(),
    );
    final balance = tab.netBalanceCentavos > 0
        ? '${friend.displayName} owes you $amount'
        : tab.netBalanceCentavos < 0
        ? 'You owe ${friend.displayName} $amount'
        : 'All settled — $amount';
    final action = await _confirm<String>(
      (dialog) => AlertDialog(
        scrollable: true,
        title: Text('You already have a tab with ${friend.displayName}'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You already have a shared tab with this person. Would you like to add a new expense or view your existing transactions?',
            ),
            const SizedBox(height: 16),
            Text(balance, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'view'),
            child: const Text('View Existing Tab'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, 'add'),
            child: const Text('Add New Expense'),
          ),
        ],
      ),
    );
    if (!mounted || !_current || action == null) return;
    if (action == 'view') {
      final router = GoRouter.of(context);
      _allowExit = true;
      Navigator.pop(context);
      router.go('/tabs/${tab.id}');
      return;
    }
    setState(() {
      _selectedFriendIds
        ..clear()
        ..add(friend.id);
      _unregisteredName = null;
      _selectedExistingGroupId = null;
      _selectedExistingGroupName = null;
      _existingBilateralId = tab.id;
      _tabNameController.text = friend.displayName;
      _step = 1;
    });
  }

  void _addUnregisteredPerson() {
    final name = _unregisteredNameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a name for the unregistered person.');
      return;
    }

    setState(() {
      _existingBilateralId = null;
      _selectedExistingGroupId = null;
      _selectedExistingGroupName = null;
      if (_unregisteredName != null && _unregisteredName != name) {
        _newContactId = const Uuid().v4();
      }
      _unregisteredName = name;
      if (_selectedFriendIds.isEmpty) {
        _tabNameController.text = name;
      }
      _unregisteredNameController.clear();
    });
  }

  void _removeUnregisteredPerson() {
    setState(() {
      _existingBilateralId = null;
      _unregisteredName = null;
      _newContactId = const Uuid().v4();
      if (_selectedFriendIds.isEmpty) _tabNameController.clear();
    });
  }

  void _selectExistingGroup(BilateralTab group) {
    setState(() {
      _existingBilateralId = null;
      _selectedGroupPayerId = null;
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
    _leave();
  }

  void _showMessage(String message) {
    if (!_current) return;
    TabbyFeedback.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Retain encrypted owned receipt bytes in the draft. The financial executor
  /// uploads them when the user submits; picker cache paths are never durable.
  Future<void> _attachReceipt() async {
    if (_isPicking || _isSubmitting || _attempted || !_draftReady) return;
    setState(() => _isPicking = true);
    try {
      final source = await ReceiptSourceSheet.show(context);
      if (source == null || !_current) return;
      await _persistDraft();
      if (!_current) return;
      final file = await ReceiptAttachmentService.pickImage(
        source,
        ownerId: _owner,
        purpose: _purpose,
      );
      if (file == null || !_current) return;
      await _retainReceipt(file);
      if (_current) {
        setState(() {});
        _showMessage('Receipt image attached.');
      }
    } catch (_) {
      if (_current) {
        _showMessage(
          'Receipt could not be saved. Your draft is kept for retry.',
        );
      }
    } finally {
      if (_current) setState(() => _isPicking = false);
    }
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

  List<TabbyUser> get _allocationMembers {
    if (_selectedExistingGroupId != null || _selectedFriendIds.length > 1) {
      return _groupMembers;
    }
    final friend = _selectedFriends(ref.read(friendsProvider)).firstOrNull;
    return [
      ref.read(currentUserProvider),
      friend ??
          TabbyUser(
            id: _newContactId,
            displayName: _unregisteredName ?? 'Other person',
            email: '',
            phone: '',
          ),
    ];
  }

  String get _payerId =>
      _selectedExistingGroupId != null || _selectedFriendIds.length > 1
      ? _groupPayer?.id ?? _owner
      : _paidByMe
      ? _owner
      : _allocationMembers.last.id;

  TextEditingController _customController(String id) =>
      _customInputs.putIfAbsent(id, () {
        final controller = TextEditingController();
        controller.addListener(_changed);
        return controller;
      });

  Map<String, int>? _customAmounts(int total) {
    if (!_customSplit) return null;
    final amounts = {
      for (final m in _allocationMembers)
        m.id: CurrencyFormatter.parseToCentavos(_customController(m.id).text),
    };
    LedgerValidation.customShares(
      total: total,
      members: _allocationMembers,
      payerId: _payerId,
      amounts: amounts,
    );
    return amounts;
  }

  Map<String, int> _sharesFor(int total) {
    final custom = _customAmounts(total);
    if (custom != null) return custom;
    if (_allocationMembers.length > 2 || _selectedExistingGroupId != null) {
      return {
        for (final p in LedgerValidation.groupShares(
          total: total,
          members: _allocationMembers,
          payerId: _payerId,
          equalSplit: _isEqualSplit,
        ))
          p.userId: p.shareAmountCentavos,
      };
    }
    final own = _isEqualSplit
        ? total ~/ 2
        : _paidByMe
        ? 0
        : total;
    return {_owner: own, _allocationMembers.last.id: total - own};
  }

  BilateralTab? get _targetTab {
    final id =
        _selectedExistingGroupId ??
        _existingBilateralId ??
        (_selectedFriendIds.length == 1
            ? _selectedFriendIds.first
            : _newContactId);
    return ref
        .read(tabbyProvider)
        .tabs
        .where((t) => t.id == id || (!t.isGroupTab && t.counterpart.id == id))
        .firstOrNull;
  }

  Future<void> _submitCreateTab() async {
    if (_isSubmitting ||
        _isPicking ||
        _isChecking ||
        !_current ||
        !_draftReady) {
      return;
    }

    final error = _participantError;
    if (error != null) {
      setState(() => _step = 0);
      _showMessage(error);
      return;
    }

    final int centavos;
    try {
      centavos = CurrencyFormatter.parseToCentavos(_amountController.text);
    } on FormatException catch (error) {
      setState(() => _amountError = error.message);
      return;
    }
    if (centavos <= 0) {
      setState(
        () => _amountError = 'Please enter an amount greater than PHP 0.00',
      );
      return;
    }

    final tabName = _tabNameController.text.trim().isEmpty
        ? _selectedParticipantName
        : _tabNameController.text.trim();
    if (tabName.isEmpty) {
      _showMessage('Please enter a tab name.');
      return;
    }

    setState(() => _isChecking = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      _customAmounts(
        centavos,
      ); // Validate before any network or financial write.
      if (!_attempted) {
        final notifier = ref.read(tabbyProvider.notifier);
        if (_selectedFriendIds.length == 1 &&
            !_createGroup &&
            _existingBilateralId == null) {
          final friend = _selectedFriends(ref.read(friendsProvider)).single;
          final existing = await notifier.inspectSharedTab(friend.id);
          if (!_current) return;
          if (existing != null) {
            await _showExistingTab(existing, friend);
            return;
          }
        }
        if (SupabaseConfig.isInitialized &&
            !await notifier.refreshExpenseHistory()) {
          if (_current) {
            _showMessage(
              'Could not check existing expenses. Your draft is kept. Reconnect and try again.',
            );
          }
          return;
        }
        if (!_current) return;
        final tab = _targetTab;
        if (tab != null) {
          final fingerprint = ExpenseDraftFingerprint(
            tabId: tab.id,
            amountCentavos: centavos,
            description: _expenseTitle,
            category: _selectedCategory,
            payerId: _payerId,
            date: DateTime.now(),
            shares: _sharesFor(centavos),
          );
          final candidate = tab.entries
              .where(
                (entry) => fingerprint.matches(
                  entry,
                  viewerId: _owner,
                  counterpartId: tab.counterpart.id,
                  operationId: _expenseOperationId,
                ),
              )
              .firstOrNull;
          if (candidate != null) {
            final snapshot = _snapshot().toString();
            final action = await _showDuplicateWarning(candidate);
            if (!_current ||
                action != 'add' ||
                snapshot != _snapshot().toString()) {
              return;
            }
          }
        }
      }
      if (_current) {
        await _commitCreateTab(centavos: centavos, tabName: tabName);
      }
    } on TabValidationException catch (error) {
      if (_current) _showMessage(error.message);
    } on FormatException {
      if (_current) {
        _showMessage(
          'Enter a valid amount for each person, including 0 for anyone with no share.',
        );
      }
    } catch (_) {
      if (_current) {
        _showMessage(
          'Could not check this tab. Your draft is kept. Please try again.',
        );
      }
    } finally {
      if (_current) setState(() => _isChecking = false);
    }
  }

  Future<String?> _showDuplicateWarning(LedgerEntry entry) async {
    final action = await _confirm<String>(
      (dialog) => AlertDialog(
        scrollable: true,
        title: const Text('Possible Duplicate Expense'),
        content: const Text(
          'A similar expense has already been recorded in this tab. Are you sure this is a new transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'review'),
            child: const Text('Review Existing Expense'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, 'add'),
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );
    if (action == 'review' && mounted && _current) {
      await _confirm<void>(
        (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('Existing Expense'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.title),
              const SizedBox(height: 8),
              Text(CurrencyFormatter.formatCentavos(entry.totalAmountCentavos)),
              Text(
                'Paid by ${entry.paidByUserId == _owner ? 'you' : entry.paidByName}',
              ),
              Text(DateFormat.yMMMd().add_jm().format(entry.date.toLocal())),
              Text(entry.category.displayName),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Back to Expense'),
            ),
          ],
        ),
      );
    }
    return action;
  }

  Future<T?> _confirm<T>(WidgetBuilder builder) async {
    if (!_current) return null;
    setState(() => _confirmationOpen = true);
    try {
      return await showDialog<T>(
        context: context,
        animationStyle: TabbyMotion.style(context),
        builder: (dialog) => AccountDraftGuard(child: builder(dialog)),
      );
    } finally {
      if (_current) setState(() => _confirmationOpen = false);
    }
  }

  Future<void> _commitCreateTab({
    required int centavos,
    required String tabName,
  }) async {
    if (_isSubmitting) return;
    if (!_draftReady || !_current) return;
    final retrying = _attempted;
    setState(() {
      _isSubmitting = true;
      _attempted = true;
    });
    try {
      _lastDraft = '';
      await _persistDraft();
    } catch (_) {
      if (_current) setState(() => _isSubmitting = false);
      return;
    }
    if (!_current) return;

    final notifier = ref.read(tabbyProvider.notifier);
    final friends = ref.read(friendsProvider);
    final selectedFriends = _selectedFriends(friends);
    final title = _expenseTitle;

    try {
      if (selectedFriends.length > 1) {
        final groupId = await notifier.createGroupTab(
          operationId: _groupCreationOperationId,
          groupName: tabName,
          memberNames: selectedFriends
              .map((friend) => friend.displayName)
              .toList(),
          memberUserIds: selectedFriends.map((friend) => friend.id).toList(),
        );
        if (groupId == null || groupId.isEmpty) {
          if (!_current) return;
          setState(() => _isSubmitting = false);
          _showMessage('The group tab could not be created. Please try again.');
          return;
        }

        await notifier.addExpense(
          customAmounts: _customAmounts(centavos),
          operationId: _expenseOperationId,
          counterpartId: groupId,
          counterpartName: tabName,
          title: title,
          totalAmountCentavos: centavos,
          category: _selectedCategory,
          paidByMe: _groupPayer?.id == ref.read(currentUserProvider).id,
          isEqualSplit: _isEqualSplit,
          participantCount: selectedFriends.length + 1,
          payerId: _groupPayer?.id,
          payerName: _groupPayer?.displayName,
          dueDate: _selectedDueDate,
          receiptUrl: _receiptUrl,
        );
      } else if (_selectedExistingGroupId != null) {
        await notifier.addExpense(
          customAmounts: _customAmounts(centavos),
          operationId: _expenseOperationId,
          counterpartId: _selectedExistingGroupId!,
          counterpartName: _selectedExistingGroupName ?? tabName,
          title: title,
          totalAmountCentavos: centavos,
          category: _selectedCategory,
          paidByMe: _groupPayer?.id == ref.read(currentUserProvider).id,
          payerId: _groupPayer?.id,
          payerName: _groupPayer?.displayName,
          isEqualSplit: _isEqualSplit,
          dueDate: _selectedDueDate,
          receiptUrl: _receiptUrl,
        );
      } else {
        final friend = selectedFriends.firstOrNull;
        final name = friend?.displayName ?? _unregisteredName ?? tabName;
        final id = _existingBilateralId ?? friend?.id ?? _newContactId;
        await notifier.addExpense(
          customAmounts: _customAmounts(centavos),
          operationId: _expenseOperationId,
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

      if (!_current) return;
      if (retrying && SupabaseConfig.isInitialized) {
        await notifier.synchronize();
      }
      if (!_current) return;
      final pending = SupabaseConfig.isInitialized
          ? (await TabbyLocalCache.loadPendingOps(userId: _owner, strict: true))
                .where((op) => op['operation_id'] == _expenseOperationId)
                .firstOrNull
          : null;
      final mapped =
          !SupabaseConfig.isInitialized ||
          await TabbyLocalCache.loadEntryMapping(
                'entry-$_expenseOperationId',
                userId: _owner,
              ) !=
              null;
      if (!_current) return;
      _pendingSave = pending != null || !mapped;
      _needsAttention = pending?['sync_state'] == 'needsAttention';
      if (!_pendingSave) await _draftStore.remove(_owner, _purpose);
      if (!_current) return;
      setState(() {
        _isSubmitting = false;
        _hasCreatedTab = true;
        _step = 2;
      });
    } catch (error) {
      if (!_current) return;
      setState(() => _isSubmitting = false);
      _showMessage(
        error is TabValidationException
            ? error.message
            : 'The tab could not be created. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final groups = ref.watch(groupsProvider);

    return AccountDraftGuard(
      child: PopScope<Object?>(
        canPop:
            _allowExit ||
            _hasCreatedTab ||
            (_draftReady && !_dirty && !_isSubmitting),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Container(
          constraints: isTabbyFormPage(context)
              ? null
              : const BoxConstraints(maxHeight: 760),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: TabbyPalette.of(context).surface,
            borderRadius: isTabbyFormPage(context)
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(36)),
          ),
          child: TabbyFormBody(
            header: _buildHeader(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isTabbyFormPage(context))
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: TabbyPalette.of(context).border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                if (!isTabbyFormPage(context)) const SizedBox(height: 12),
                if (_draftError != null)
                  Row(
                    children: [
                      Expanded(child: Text(_draftError!)),
                      TextButton(
                        onPressed: () async {
                          if (!_draftReady) {
                            await _restoreDraft();
                            return;
                          }
                          _lastDraft = '';
                          try {
                            await _persistDraft();
                            if (_current) {
                              super.setState(() => _draftError = null);
                            }
                          } catch (_) {}
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                _buildProgress(),
                const SizedBox(height: 14),
                IgnorePointer(
                  ignoring:
                      (_attempted && !_hasCreatedTab) ||
                      !_draftReady ||
                      _isPicking ||
                      _isChecking,
                  child: AnimatedSwitcher(
                    duration: TabbyMotion.duration(
                      context,
                      const Duration(milliseconds: 180),
                    ),
                    child: _step == 0
                        ? _buildAddPeople(friends, groups)
                        : _step == 1
                        ? _buildDetails()
                        : _buildDone(),
                  ),
                ),
                if (_step == 1) ...[
                  const SizedBox(height: 10),
                  _primaryAction(
                    label: _attempted
                        ? 'Retry Save'
                        : _addingToTab
                        ? 'Add to Tab'
                        : 'Create Tab',
                    isLoading:
                        (_isSubmitting || _isChecking) && !_confirmationOpen,
                    onPressed: _isSubmitting || _isChecking || !_draftReady
                        ? null
                        : _submitCreateTab,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          tooltip: _step == 0 && !isTabbyFormPage(context) ? 'Close' : 'Back',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            _step == 0 && !isTabbyFormPage(context)
                ? Icons.close_rounded
                : Icons.arrow_back_rounded,
            color: TabbyPalette.of(context).text,
          ),
          onPressed: _goBack,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _addingToTab ? 'Add to Tab' : 'Create Tab',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: TabbyPalette.of(context).text,
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (_step == 0 && MediaQuery.textScalerOf(context).scale(20) <= 26)
          Text(
            '${_selectedFriendIds.length + (_unregisteredName == null ? 0 : 1)} selected',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: TabbyPalette.of(context).secondaryText,
            ),
          ),
      ],
    );
  }

  Widget _buildProgress() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _buildProgressStep(1, 'Add People', _step >= 0),
        ),
        _buildProgressLine(_step >= 1),
        Expanded(flex: 3, child: _buildProgressStep(2, 'Details', _step >= 1)),
        _buildProgressLine(_step >= 2),
        Expanded(flex: 3, child: _buildProgressStep(3, 'Done', _step >= 2)),
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
            color: active
                ? TabbyColors.brandAmber
                : TabbyPalette.of(context).soft,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active
                  ? TabbyColors.brandInk
                  : TabbyPalette.of(context).text,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active
                ? TabbyPalette.of(context).text
                : TabbyPalette.of(context).secondaryText,
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
        color: active
            ? TabbyColors.brandAmber
            : TabbyPalette.of(context).border,
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
        Text(
          'Add People',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: TabbyPalette.of(context).text,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Choose your Tabby friends or add one person by name.',
          style: TextStyle(
            fontSize: 12,
            color: TabbyPalette.of(context).secondaryText,
          ),
        ),
        const SizedBox(height: 14),
        if (widget.initialCounterpartId == null) ...[
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Create a group tab'),
              subtitle: const Text(
                'Choose two or more friends for one shared expense.',
              ),
              value: _createGroup,
              onChanged: (value) => setState(() {
                ++_selectionRevision;
                _createGroup = value;
                _selectedFriendIds.clear();
                _existingBilateralId = null;
                _selectedExistingGroupId = null;
                _selectedExistingGroupName = null;
                _unregisteredName = null;
                _tabNameController.clear();
              }),
            ),
          ),
          const SizedBox(height: 8),
        ],
        _buildSearchField(),
        const SizedBox(height: 16),
        Text(
          'Friends',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: TabbyPalette.of(context).text,
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
                activeColor: TabbyColors.brandAmber,
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: _buildAvatar(friend.displayName),
                title: Text(
                  friend.displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TabbyPalette.of(context).text,
                  ),
                ),
                subtitle: Text(
                  friend.friendCode?.trim().isNotEmpty == true
                      ? 'Connected'
                      : 'Registered friend',
                  style: TextStyle(
                    fontSize: 10,
                    color: TabbyPalette.of(context).secondaryText,
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
          Text(
            'Existing Groups',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: TabbyPalette.of(context).text,
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
                selectedColor: TabbyColors.brandAmber,
                labelStyle: TextStyle(
                  color: selected
                      ? TabbyColors.brandInk
                      : TabbyPalette.of(context).text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => _selectExistingGroup(group),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Unregistered person',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: TabbyPalette.of(context).text,
          ),
        ),
        const SizedBox(height: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('create-tab-unregistered-name'),
              controller: _unregisteredNameController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addUnregisteredPerson(),
              decoration: _inputDecoration(
                hintText: 'Add someone not on Tabby',
                icon: Icons.person_add_alt_1_rounded,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _addUnregisteredPerson,
              style: OutlinedButton.styleFrom(
                foregroundColor: TabbyPalette.of(context).link,
                side: BorderSide(color: TabbyPalette.of(context).controlBorder),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
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
            backgroundColor: TabbyPalette.of(context).soft,
          ),
        ],
        const SizedBox(height: 18),
        _primaryAction(
          label: 'Next',
          onPressed: _isChecking ? null : _goToDetails,
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
        Text(
          'Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: TabbyPalette.of(context).text,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _addingToTab
              ? 'Record a new expense in your existing tab.'
              : isGroup
              ? 'Set the name and first expense for this group tab.'
              : 'Add the details for this new tab.',
          style: TextStyle(
            fontSize: 12,
            color: TabbyPalette.of(context).secondaryText,
          ),
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
        Text(
          'Amount',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TabbyPalette.of(context).secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: TabbyPalette.of(context).soft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Text(
                '₱',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: TabbyPalette.of(context).text,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('create-tab-amount'),
                  controller: _amountController,
                  onChanged: (_) => setState(() => _amountError = null),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: TabbyPalette.of(context).text,
                  ),
                  decoration: InputDecoration(
                    errorText: _amountError,
                    hintText: '0.00',
                    hintStyle: TextStyle(
                      color: TabbyPalette.of(context).secondaryText,
                    ),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: TabbyPalette.of(context).text,
                  ),
                ),
                backgroundColor: TabbyPalette.of(context).soft,
                padding: EdgeInsets.zero,
                onPressed: () {
                  final current = CurrencyFormatter.tryParseToCentavos(
                    _amountController.text,
                  );
                  if (current == null &&
                      _amountController.text.trim().isNotEmpty) {
                    setState(
                      () => _amountError = 'Enter a valid PHP amount first.',
                    );
                    return;
                  }
                  final newAmount = (current ?? 0) + (amount * 100);
                  if (newAmount > CurrencyFormatter.maxAmountCentavos) {
                    setState(
                      () => _amountError =
                          'The maximum amount is PHP 999,999,999.99.',
                    );
                    return;
                  }
                  _amountController.text = (newAmount / 100).toStringAsFixed(2);
                  setState(() => _amountError = null);
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
                child: isGroup
                    ? DropdownButtonFormField<String>(
                        initialValue: _groupPayer?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Who paid?',
                        ),
                        items: _groupMembers
                            .map(
                              (m) => DropdownMenuItem(
                                value: m.id,
                                child: Text(
                                  m.id == ref.read(currentUserProvider).id
                                      ? 'You'
                                      : m.displayName,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) =>
                            setState(() => _selectedGroupPayerId = id),
                      )
                    : SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text(
                              'I paid',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text(
                              'They paid',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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
                label: _customSplit ? 'Split: Custom amounts' : 'Split',
                child: SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(
                      value: true,
                      label: Text(
                        'Equal',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(
                        isGroup ? 'Others split' : 'Full share',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  selected: _customSplit ? <bool>{} : {_isEqualSplit},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (selection) => setState(() {
                    if (selection.isNotEmpty) _isEqualSplit = selection.first;
                    _customSplit = false;
                  }),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom amounts'),
            subtitle: const Text(
              'Set each person’s share. Your share can be 0.',
            ),
            value: _customSplit,
            onChanged: (value) => setState(() => _customSplit = value),
          ),
        ),
        if (_customSplit) ...[
          for (final member in _allocationMembers) ...[
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('custom-share-${member.id}'),
              controller: _customController(member.id),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
                  _inputDecoration(
                    hintText: '0.00',
                    icon: Icons.payments_outlined,
                  ).copyWith(
                    labelText:
                        '${member.id == _owner ? 'Your' : '${member.displayName}’s'} share (PHP)',
                  ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Allocated: ${CurrencyFormatter.formatCentavos(_allocationMembers.fold<int>(0, (sum, m) => sum + (CurrencyFormatter.tryParseToCentavos(_customController(m.id).text) ?? 0)))} of ${CurrencyFormatter.formatCentavos(CurrencyFormatter.tryParseToCentavos(_amountController.text) ?? 0)}',
          ),
          const SizedBox(height: 8),
        ],
        if (isGroup && !_customSplit) ...[
          if (_groupMembers.length < 2 || _groupPayer == null)
            const Text(
              'Refresh this group to load its members before adding an expense.',
            )
          else if ((CurrencyFormatter.tryParseToCentavos(
                    _amountController.text,
                  ) ??
                  0) >
              0)
            ...LedgerValidation.groupShares(
              total: CurrencyFormatter.parseToCentavos(_amountController.text),
              members: _groupMembers,
              payerId: _groupPayer!.id,
              equalSplit: _isEqualSplit,
            ).map(
              (p) => Text(
                '${p.userId == ref.read(currentUserProvider).id ? 'You' : p.name}: ${CurrencyFormatter.formatCentavos(p.shareAmountCentavos)}',
              ),
            ),
          const SizedBox(height: 8),
        ],
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
            if (_receiptUrl == null) {
              _attachReceipt();
            } else {
              setState(() => _receiptUrl = null);
            }
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
        Text(
          'Category',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TabbyPalette.of(context).secondaryText,
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
                    ? TabbyColors.brandInk
                    : TabbyPalette.of(context).text,
              ),
              label: Text(category.displayName),
              selected: selected,
              selectedColor: TabbyColors.brandAmber,
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected
                    ? TabbyColors.brandInk
                    : TabbyPalette.of(context).text,
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
        TabbyMascotWidget.art(
          pose: _pendingSave
              ? TabbyMascotPose.waiting
              : TabbyMascotPose.celebrating,
          size: 112,
        ),
        const SizedBox(height: 16),
        Text(
          _needsAttention
              ? 'Save needs attention'
              : _pendingSave
              ? 'Expense queued'
              : 'Expense recorded',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: TabbyPalette.of(context).text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _needsAttention
              ? 'Your expense is kept safely. Open sync status to review it before retrying.'
              : _pendingSave
              ? 'Your expense is saved on this device and waiting for server confirmation. Retry the same draft when connected.'
              : 'Your expense with $_selectedParticipantName is saved. Your tab balance has been updated.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: TabbyPalette.of(context).secondaryText,
          ),
        ),
        const SizedBox(height: 24),
        _primaryAction(label: 'Done', onPressed: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildSegmentField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TabbyPalette.of(context).secondaryText,
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
        Icon(icon, size: 19, color: TabbyPalette.of(context).text),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: TabbyPalette.of(context).text,
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
                  ? TabbyPalette.of(context).errorText
                  : TabbyPalette.of(context).link,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await TabbyMotion.datePicker(
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
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TabbyPalette.of(context).secondaryText,
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

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: TabbyPalette.of(context).secondaryText,
        fontSize: 13,
      ),
      prefixIcon: Icon(
        icon,
        size: 18,
        color: TabbyPalette.of(context).secondaryText,
      ),
      filled: true,
      fillColor: TabbyPalette.of(context).soft,
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
      backgroundColor: TabbyPalette.of(context).soft,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: TabbyPalette.of(context).text,
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
        color: TabbyPalette.of(context).soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12,
          color: TabbyPalette.of(context).secondaryText,
        ),
      ),
    );
  }
}
