import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../application/classroom_providers.dart';
import '../domain/classroom_models.dart';
import 'task_card_widget.dart';

class ClassroomConnectSheet extends ConsumerStatefulWidget {
  const ClassroomConnectSheet({super.key});

  @override
  ConsumerState<ClassroomConnectSheet> createState() =>
      _ClassroomConnectSheetState();
}

class _ClassroomConnectSheetState extends ConsumerState<ClassroomConnectSheet> {
  bool _isLoading = false;

  Future<void> _connect() async {
    setState(() => _isLoading = true);
    final connected =
        await ref.read(classroomConnectionProvider.notifier).connect();
    if (connected && mounted) {
      await _syncData();
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!connected) {
      _showMessage('Google Classroom could not be connected.');
    }
  }

  Future<void> _syncData() async {
    await ref.read(classroomCoursesProvider.notifier).refresh();
    final courses = ref.read(classroomCoursesProvider);
    await ref.read(classroomTasksProvider.notifier).refresh(courses: courses);
    await ref
        .read(classroomAnnouncementsProvider.notifier)
        .refresh(courses: courses);
  }

  Future<void> _syncNow() async {
    setState(() => _isLoading = true);
    try {
      await _syncData();
      if (mounted) _showMessage('Classroom tasks are up to date.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _disconnect() async {
    final shouldDisconnect = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Google Classroom?'),
        content: const Text(
            'Tabby will remove synced courses, tasks, and reminders from this account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: TabbyColors.alertRed),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (shouldDisconnect != true) return;
    setState(() => _isLoading = true);
    await ref.read(classroomConnectionProvider.notifier).disconnect();
    if (mounted) {
      ref.read(classroomCoursesProvider.notifier).clear();
      ref.read(classroomTasksProvider.notifier).clear();
      ref.read(classroomAnnouncementsProvider.notifier).clear();
      Navigator.of(context).pop();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(classroomConnectionProvider);
    final courses = ref.watch(classroomCoursesProvider);
    final isConnected = connection?.isActive == true;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: TabbyColors.borderMint,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            if (isConnected)
              _buildConnectedState(connection!, courses)
            else
              _buildInitialState(),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle(
          icon: Icons.school_outlined,
          iconColor: TabbyColors.accentBlue,
          title: 'Connect Google Classroom',
          subtitle:
              'Tabby reads your assignments and sets reminders. It never posts for you.',
        ),
        const SizedBox(height: 22),
        const Text(
          'What Tabby accesses',
          style: TextStyle(
            color: TabbyColors.brandDarkTeal,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        _buildAccessRow(Icons.check_circle_rounded, 'Your enrolled courses',
            TabbyColors.brandEmerald),
        _buildAccessRow(Icons.check_circle_rounded,
            'Assignment titles and due dates', TabbyColors.brandEmerald),
        _buildAccessRow(Icons.check_circle_rounded, 'Teacher announcements',
            TabbyColors.brandEmerald),
        _buildAccessRow(Icons.cancel_rounded, 'Tabby never submits assignments',
            TabbyColors.textSecondary),
        const SizedBox(height: 22),
        TabbyButton(
          label: 'Connect with Google',
          isLoading: _isLoading,
          icon: const Icon(Icons.login_rounded, size: 18),
          onPressed: _connect,
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedState(
      ClassroomConnection connection, List<ClassroomCourse> courses) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle(
          icon: Icons.check_circle_rounded,
          iconColor: TabbyColors.brandEmerald,
          title: 'Connected',
          subtitle:
              '${connection.googleEmail} · ${courses.length} courses synced',
        ),
        const SizedBox(height: 22),
        const Text(
          'Courses',
          style: TextStyle(
            color: TabbyColors.brandDarkTeal,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (courses.isEmpty)
          const Text(
            'No active courses were found.',
            style: TextStyle(color: TabbyColors.textSecondary),
          )
        else
          ...courses.map(_buildCourseRow),
        const SizedBox(height: 18),
        const Text(
          'Reminder alarms',
          style: TextStyle(
            color: TabbyColors.brandDarkTeal,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        _buildAlarmSwitch(
          title: '60 minutes before',
          value: connection.alarm60mEnabled,
          onChanged: (value) => ref
              .read(classroomConnectionProvider.notifier)
              .updateAlarmSettings(alarm60mEnabled: value),
        ),
        _buildAlarmSwitch(
          title: '30 minutes before',
          value: connection.alarm30mEnabled,
          onChanged: (value) => ref
              .read(classroomConnectionProvider.notifier)
              .updateAlarmSettings(alarm30mEnabled: value),
        ),
        _buildAlarmSwitch(
          title: '10 minutes before',
          value: connection.alarm10mEnabled,
          onChanged: (value) => ref
              .read(classroomConnectionProvider.notifier)
              .updateAlarmSettings(alarm10mEnabled: value),
        ),
        const SizedBox(height: 12),
        TabbyButton(
          label: 'Sync Now',
          isLoading: _isLoading,
          icon: const Icon(Icons.sync_rounded, size: 18),
          onPressed: _syncNow,
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _disconnect,
            style: TextButton.styleFrom(foregroundColor: TabbyColors.alertRed),
            child: const Text('Disconnect Classroom'),
          ),
        ),
      ],
    );
  }

  Widget _buildTitle({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: TabbyColors.brandDarkTeal,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: TabbyColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccessRow(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: TabbyColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseRow(ClassroomCourse course) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: classroomColorFromHex(course.colorHex),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              course.section?.isNotEmpty == true
                  ? '${course.section} — ${course.name}'
                  : course.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: TabbyColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: const TextStyle(
          color: TabbyColors.textSecondary,
          fontSize: 13,
        ),
      ),
      value: value,
      activeThumbColor: TabbyColors.brandEmerald,
      onChanged: _isLoading ? null : onChanged,
    );
  }
}
