import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tabby_colors.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/domain/models.dart';
import '../application/classroom_providers.dart';
import '../domain/classroom_models.dart';
import 'classroom_connect_sheet.dart';
import 'task_card_widget.dart';

class ClassroomTasksScreen extends ConsumerStatefulWidget {
  const ClassroomTasksScreen({super.key});

  @override
  ConsumerState<ClassroomTasksScreen> createState() =>
      _ClassroomTasksScreenState();
}

class _ClassroomTasksScreenState extends ConsumerState<ClassroomTasksScreen> {
  String? _selectedCourseId;

  Future<void> _refresh() async {
    await ref.read(classroomCoursesProvider.notifier).refresh();
    final courses = ref.read(classroomCoursesProvider);
    await ref.read(classroomTasksProvider.notifier).refresh(courses: courses);
    await ref
        .read(classroomAnnouncementsProvider.notifier)
        .refresh(courses: courses);
  }

  void _openConnectionSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TabbyColors.surfaceWhite,
      builder: (_) => const ClassroomConnectSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(classroomConnectionProvider);
    final courses = ref.watch(classroomCoursesProvider);
    final allTasks = ref.watch(filteredTasksProvider(_selectedCourseId));
    final announcements = ref.watch(classroomAnnouncementsProvider);
    final dueTodayCount = ref.watch(tasksDueTodayCountProvider);
    final isConnected = connection?.isActive == true;

    return Scaffold(
      backgroundColor: TabbyColors.brandEmerald,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: TabbyColors.brandEmerald,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                  child: _buildHeader(dueTodayCount, isConnected)),
              SliverToBoxAdapter(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 560),
                  decoration: const BoxDecoration(
                    color: TabbyColors.surfaceWhite,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
                  child: isConnected
                      ? _buildConnectedBody(allTasks, courses, announcements)
                      : const _ClassroomEmptyState(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int dueTodayCount, bool isConnected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Tasks',
                  style: TextStyle(
                    color: TabbyColors.surfaceWhite,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$dueTodayCount due today',
                  style: TextStyle(
                    color: TabbyColors.surfaceWhite.withValues(alpha: 0.82),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _openConnectionSheet,
            tooltip: isConnected ? 'Classroom settings' : 'Connect Classroom',
            style: IconButton.styleFrom(
              backgroundColor: TabbyColors.surfaceWhite.withValues(alpha: 0.18),
              foregroundColor: TabbyColors.surfaceWhite,
            ),
            icon: Icon(
                isConnected ? Icons.settings_outlined : Icons.school_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedBody(
    List<ClassroomTask> tasks,
    List<ClassroomCourse> courses,
    List<ClassroomAnnouncement> announcements,
  ) {
    final overdue = tasks.where(_isOverdue).toList();
    final dueToday = tasks.where(_isDueToday).toList();
    final dueThisWeek = tasks.where((task) {
      if (!_isAssignedWithDueDate(task) ||
          _isDueToday(task) ||
          _isOverdue(task)) {
        return false;
      }
      final dueAt = task.dueAt!;
      final now = DateTime.now();
      return dueAt.isAfter(now) &&
          dueAt.isBefore(now.add(const Duration(days: 7)));
    }).toList();
    final upcoming = tasks.where((task) {
      if (!_isAssignedWithDueDate(task) || _isOverdue(task)) return false;
      return task.dueAt!.isAfter(DateTime.now().add(const Duration(days: 7)));
    }).toList();
    final noDueDate = tasks
        .where((task) =>
            task.state == ClassroomTaskState.assigned && task.dueAt == null)
        .toList();
    final submitted = tasks
        .where((task) => task.state != ClassroomTaskState.assigned)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (courses.isNotEmpty)
          _CourseFilterRow(
            courses: courses,
            selectedCourseId: _selectedCourseId,
            onSelected: (courseId) =>
                setState(() => _selectedCourseId = courseId),
          ),
        _buildTaskSection('Overdue', overdue),
        _buildTaskSection('Due Today', dueToday),
        _buildTaskSection('Due This Week', dueThisWeek),
        _buildTaskSection('Upcoming', upcoming),
        _buildTaskSection('No Due Date', noDueDate),
        _buildAnnouncementsSection(announcements),
        if (submitted.isNotEmpty) _buildSubmittedSection(submitted),
        if (overdue.isEmpty &&
            dueToday.isEmpty &&
            dueThisWeek.isEmpty &&
            upcoming.isEmpty &&
            noDueDate.isEmpty &&
            announcements.isEmpty &&
            submitted.isEmpty)
          _buildNoTasksState(),
      ],
    );
  }

  Widget _buildTaskSection(String title, List<ClassroomTask> tasks) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return _TaskSection(title: title, tasks: tasks);
  }

  Widget _buildSubmittedSection(List<ClassroomTask> tasks) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        color: TabbyColors.bgCanvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        initiallyExpanded: false,
        title: Text(
          'Submitted (${tasks.length})',
          style: const TextStyle(
            color: TabbyColors.brandDarkTeal,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        children: tasks.map((task) => TaskCardWidget(task: task)).toList(),
      ),
    );
  }

  Widget _buildAnnouncementsSection(List<ClassroomAnnouncement> announcements) {
    if (announcements.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: _TaskSection(
        title: 'Announcements',
        tasks: const [],
        extra: announcements
            .take(5)
            .map((announcement) => _AnnouncementCard(
                  announcement: announcement,
                  onRead: () => ref
                      .read(classroomAnnouncementsProvider.notifier)
                      .markRead(announcement.id),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildNoTasksState() {
    return const Center(
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 56, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.task_alt_rounded,
                  size: 52, color: TabbyColors.brandEmerald),
              SizedBox(height: 14),
              Text(
                'All clear for now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: TabbyColors.brandDarkTeal,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'New assignments will appear here after your next sync.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: TabbyColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isAssignedWithDueDate(ClassroomTask task) =>
      task.state == ClassroomTaskState.assigned && task.dueAt != null;

  bool _isDueToday(ClassroomTask task) {
    if (!_isAssignedWithDueDate(task)) return false;
    final now = DateTime.now();
    final dueAt = task.dueAt!;
    return dueAt.year == now.year &&
        dueAt.month == now.month &&
        dueAt.day == now.day;
  }

  bool _isOverdue(ClassroomTask task) {
    if (task.state != ClassroomTaskState.assigned || task.dueAt == null) {
      return false;
    }
    final now = DateTime.now();
    return task.dueAt!.isBefore(now) && !_isDueToday(task);
  }
}

class _ClassroomEmptyState extends StatelessWidget {
  const _ClassroomEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 55, 4, 40),
      child: Column(
        children: [
          const TabbyMascotWidget(
            emotion: MascotEmotion.idleNeutral,
            size: 94,
            showBubble: false,
          ),
          const SizedBox(height: 22),
          const Text(
            'Connect Google Classroom',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: TabbyColors.brandDarkTeal,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Get reminders for all your assignments automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: TabbyColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TabbyButton(
            label: 'Connect Classroom',
            icon: const Icon(Icons.school_outlined, size: 18),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: TabbyColors.surfaceWhite,
              builder: (_) => const ClassroomConnectSheet(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseFilterRow extends StatelessWidget {
  const _CourseFilterRow({
    required this.courses,
    required this.selectedCourseId,
    required this.onSelected,
  });

  final List<ClassroomCourse> courses;
  final String? selectedCourseId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selectedCourseId == null,
            onSelected: (_) => onSelected(null),
            selectedColor: TabbyColors.brandMintAccent,
            checkmarkColor: TabbyColors.brandDarkTeal,
          ),
          ...courses.map(
            (course) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilterChip(
                label: Text(
                  course.name.length > 12
                      ? '${course.name.substring(0, 12)}…'
                      : course.name,
                ),
                selected: selectedCourseId == course.id,
                onSelected: (_) => onSelected(course.id),
                selectedColor: classroomColorFromHex(course.colorHex)
                    .withValues(alpha: 0.2),
                checkmarkColor: classroomColorFromHex(course.colorHex),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.title,
    required this.tasks,
    this.extra = const [],
  });

  final String title;
  final List<ClassroomTask> tasks;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty && extra.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: TabbyColors.brandDarkTeal,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...tasks.map((task) => TaskCardWidget(task: task)),
          ...extra,
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement, required this.onRead});

  final ClassroomAnnouncement announcement;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: announcement.isRead ? null : onRead,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: announcement.isRead
              ? TabbyColors.bgCanvas
              : TabbyColors.brandMintAccent.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.campaign_outlined,
                color: TabbyColors.brandEmerald, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    announcement.courseName,
                    style: const TextStyle(
                      color: TabbyColors.brandDarkTeal,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    announcement.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: TabbyColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (!announcement.isRead)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.circle,
                    color: TabbyColors.brandEmerald, size: 8),
              ),
          ],
        ),
      ),
    );
  }
}
