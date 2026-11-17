import '../../../shared/widgets/tabby_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/supabase_config.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../tabs/domain/models.dart';
import '../../tabs/application/tabby_providers.dart';
import '../application/connection_preferences.dart';

class PrivateNicknameSheet extends ConsumerStatefulWidget {
  const PrivateNicknameSheet({super.key, required this.friend});
  final TabbyUser friend;
  @override
  ConsumerState<PrivateNicknameSheet> createState() =>
      _PrivateNicknameSheetState();
}

class _PrivateNicknameSheetState extends ConsumerState<PrivateNicknameSheet> {
  late final TextEditingController _name;
  late final ConnectionPreferencesNotifier _preferences;
  bool _closing = false;
  bool _edited = false;
  @override
  void initState() {
    super.initState();
    _preferences = ref.read(connectionPreferencesProvider.notifier);
    _name = TextEditingController(
        text: _preferences.snapshot.nicknames[widget.friend.id] ?? '');
    _preferences.ready.then((_) {
      if (mounted && _preferences.active && !_edited) {
        _name.text = _preferences.snapshot.nicknames[widget.friend.id] ?? '';
      }
    });
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
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider.select((user) => user.id), (previous, next) {
      if (next != _preferences.owner) _close();
    });
    final state = ref.watch(connectionPreferencesProvider);
    return PopScope(
        canPop: !state.busy,
        child: Material(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 16, 24,
                        MediaQuery.viewInsetsOf(context).bottom + 24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            const Expanded(
                                child: Text('Private nickname',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold))),
                            IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: state.busy
                                    ? null
                                    : () => Navigator.pop(context))
                          ]),
                          Text('Profile name: ${widget.friend.displayName}'),
                          const Text(
                              'Only you see this label in Connections. Their profile and receiving details stay under their control. Leave blank to use their profile name.'),
                          TextField(
                              controller: _name,
                              onChanged: (_) => _edited = true,
                              enabled: !state.busy,
                              maxLength: 80,
                              decoration:
                                  const InputDecoration(labelText: 'Nickname')),
                          if (state.error != null) Text(state.error!),
                          TabbyButton(
                              label: 'Save nickname',
                              isLoading: state.busy,
                              onPressed: state.busy || !state.loaded
                                  ? null
                                  : () async {
                                      final navigator = Navigator.of(context);
                                      final messenger =
                                          TabbyFeedback.of(context);
                                      final saved = await _preferences.change(
                                          'nickname', widget.friend.id,
                                          nickname: _name.text);
                                      if (!mounted ||
                                          !saved ||
                                          !_preferences.active) {
                                        return;
                                      }
                                      navigator.pop();
                                      messenger.showSnackBar(const SnackBar(
                                          content:
                                              Text('Private nickname saved.')));
                                    }),
                        ])))));
  }
}
