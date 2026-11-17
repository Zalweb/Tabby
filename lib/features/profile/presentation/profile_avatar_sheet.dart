import '../../../shared/widgets/tabby_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/receipt_attachment_service.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/domain/models.dart';
import '../application/profile_avatar_draft.dart';
import 'profile_avatar.dart';

class ProfileAvatarSheet extends ConsumerStatefulWidget {
  const ProfileAvatarSheet({super.key, required this.user, this.controller});
  final TabbyUser user;
  final ProfileAvatarDraft? controller;
  @override
  ConsumerState<ProfileAvatarSheet> createState() => _ProfileAvatarSheetState();
}

class _ProfileAvatarSheetState extends ConsumerState<ProfileAvatarSheet> {
  late final ProfileAvatarDraft _draft;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    final stamp = SupabaseConfig.captureSession();
    _draft = widget.controller ??
        ProfileAvatarDraft(
            owner: widget.user.id,
            isCurrent: () =>
                mounted &&
                SupabaseConfig.isCurrentSession(stamp) &&
                ref.read(currentUserProvider).id == widget.user.id,
            pick: (source) => ReceiptAttachmentService.pickImage(source,
                ownerId: widget.user.id, purpose: 'avatar'),
            upload: (path, bytes) async {
              if (!SupabaseConfig.isInitialized ||
                  SupabaseConfig.currentUserId != widget.user.id) {
                throw StateError('Sign in required');
              }
              try {
                await SupabaseConfig.client.storage
                    .from('profile-avatars')
                    .uploadBinary(path, bytes,
                        fileOptions: const FileOptions(
                            upsert: false, contentType: 'image/png'));
              } on StorageException catch (error) {
                // UUID path and owned immutable retained bytes identify this retry.
                if (error.statusCode != '409' && error.error != 'Duplicate') {
                  rethrow;
                }
              }
            },
            save: (reference) => ref
                .read(currentUserProvider.notifier)
                .updateProfile(avatarUrl: reference));
    _draft.addListener(_changed);
    _draft.restore();
    SupabaseConfig.sessionRevision.addListener(_closeForSession);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _closeForSession() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null) return;
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    SupabaseConfig.sessionRevision.removeListener(_closeForSession);
    _draft.removeListener(_changed);
    _draft.dispose();
    super.dispose();
  }

  Future<void> _saved(Future<bool> operation, String message) async {
    final accepted = await operation;
    if (!mounted || !accepted || !_draft.current) return;
    final messenger = TabbyFeedback.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (previous, next) {
      if (next.id != widget.user.id) _closeForSession();
    });
    return PopScope(
        canPop: !_draft.busy,
        child: Material(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            const Expanded(
                                child: Text('Profile Photo',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold))),
                            IconButton(
                                onPressed: _draft.busy
                                    ? null
                                    : () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded))
                          ]),
                          Center(
                              child: ClipOval(
                                  child: _draft.bytes != null
                                      ? Image.memory(_draft.bytes!,
                                          width: 96,
                                          height: 96,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, error, stack) =>
                                              const Icon(
                                                  Icons.broken_image_outlined))
                                      : ProfileAvatar(
                                          reference: ref
                                              .watch(currentUserProvider)
                                              .avatarUrl,
                                          name: widget.user.displayName,
                                          size: 96))),
                          const SizedBox(height: 12),
                          if (_draft.hasDraft) ...[
                            const Text(
                                'Selected photo is kept on this device until you save it. Your current profile photo stays in use until saving succeeds.'),
                            const SizedBox(height: 12),
                            TabbyButton(
                                label: 'Save photo',
                                isLoading: _draft.busy,
                                onPressed: _draft.busy
                                    ? null
                                    : () => _saved(_draft.apply(),
                                        'Profile photo saved.')),
                          ],
                          if (_draft.error != null) ...[
                            Text(_draft.error!),
                            TextButton(
                                onPressed: _draft.busy ? null : _draft.restore,
                                child: const Text('Retry photo draft')),
                          ],
                          ListTile(
                              leading: const Icon(Icons.photo_library_rounded),
                              title: const Text('Choose from Gallery'),
                              enabled: !_draft.busy,
                              onTap: () => _draft.choose(ImageSource.gallery)),
                          ListTile(
                              leading: const Icon(Icons.camera_alt_rounded),
                              title: const Text('Take Photo'),
                              enabled: !_draft.busy,
                              onTap: () => _draft.choose(ImageSource.camera)),
                          ListTile(
                              leading: const Icon(Icons.pets_rounded),
                              title: const Text('Tabby Mascot Style'),
                              enabled: !_draft.busy,
                              onTap: () => _saved(
                                  _draft.usePreset('asset:mascot'),
                                  'Tabby companion avatar saved.')),
                          ListTile(
                              leading: const Icon(Icons.person_outline_rounded),
                              title: const Text('Remove Photo'),
                              subtitle: const Text('Use your initials.'),
                              enabled: !_draft.busy,
                              onTap: () => _saved(_draft.usePreset(''),
                                  'Avatar reset to default initials.')),
                        ])))));
  }
}
