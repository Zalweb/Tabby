import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/config/supabase_config.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar(
      {super.key,
      required this.reference,
      required this.name,
      this.download,
      this.size = 60});
  final String? reference;
  final String name;
  final double size;
  final Future<Uint8List> Function(String path)? download;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Future<Uint8List>? _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) _load();
  }

  void _load() {
    final reference = widget.reference;
    _image = reference != null && reference.startsWith('avatar:')
        ? _download(reference.substring(7))
        : null;
  }

  Future<Uint8List> _download(String path) async {
    if (widget.download != null) return widget.download!(path);
    final stamp = SupabaseConfig.captureSession();
    if (!SupabaseConfig.isInitialized || stamp.accountId == null) {
      throw StateError('Sign in required');
    }
    final bytes = await SupabaseConfig.client.storage
        .from('profile-avatars')
        .download(path);
    if (!SupabaseConfig.isCurrentSession(stamp)) {
      throw StateError('Session changed');
    }
    return bytes;
  }

  Widget _fallback() {
    final asset = widget.reference;
    if (asset == 'asset:mascot') return const Icon(Icons.pets_rounded);
    if (asset == 'asset:cat_cool') {
      return const Icon(Icons.sentiment_very_satisfied_rounded);
    }
    if (asset == 'asset:camera_snap') {
      return const Icon(Icons.camera_alt_rounded);
    }
    final initials = widget.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join()
        .toUpperCase();
    return Text(initials.isEmpty ? '?' : initials,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold));
  }

  Widget _retry() => IconButton(
      tooltip: 'Retry profile photo',
      onPressed: () => setState(_load),
      icon: const Icon(Icons.refresh_rounded));

  @override
  Widget build(BuildContext context) => Semantics(
      label: 'Profile photo for ${widget.name}',
      image: true,
      child: SizedBox.square(
          dimension: widget.size,
          child: _image == null
              ? Center(child: _fallback())
              : FutureBuilder<Uint8List>(
                  key: ValueKey(widget.reference),
                  future: _image,
                  builder: (context, state) => state.hasError
                      ? _retry()
                      : state.connectionState == ConnectionState.done &&
                              state.hasData
                          ? Image.memory(state.data!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stack) => _retry())
                          : Center(child: _fallback()))));
}
