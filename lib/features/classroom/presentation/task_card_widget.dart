import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/tabby_colors.dart';
import '../application/classroom_providers.dart';
import '../domain/classroom_models.dart';

Color classroomUrgencyColor(TaskUrgency urgency) {
  switch (urgency) {
    case TaskUrgency.upcoming:
      return Colors.grey.shade300;
    case TaskUrgency.dueToday:
      return const Color(0xFFFFB74D);
    case TaskUrgency.dueSoon:
      return Colors.orange;
    case TaskUrgency.veryUrgent:
      return Colors.red.shade400;
    case TaskUrgency.overdue:
      return Colors.red.shade700;
    case TaskUrgency.done:
      return TabbyColors.brandEmerald;
  }
}

String classroomTimeRemainingLabel(ClassroomTask task) {
  final difference = task.timeUntilDue;
  if (difference == null) return 'No due date';
  if (difference.isNegative) return 'Overdue';
  if (difference.inHours >= 48) return '${difference.inDays} days left';
  if (difference.inHours >= 1) return '${difference.inHours} hours left';
  return '${difference.inMinutes} minutes left';
}

Color classroomColorFromHex(String value) {
  final normalized = value.replaceFirst('#', '');
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? TabbyColors.brandEmerald : Color(parsed);
}

class TaskCardWidget extends ConsumerWidget {
  const TaskCardWidget({super.key, required this.task});

  final ClassroomTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urgencyColor = classroomUrgencyColor(task.urgency);
    final isAssigned = task.state == ClassroomTaskState.assigned;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: TabbyColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TabbyColors.borderMint),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: urgencyColor,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildTaskSummary()),
                        _buildTaskMenu(context),
                      ],
                    ),
                    if (isAssigned && task.hasDueDate) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: task.classroomLink == null
                                  ? null
                                  : () => _openClassroom(context),
                              icon: const Icon(Icons.open_in_new_rounded,
                                  size: 16),
                              label: const Text('Open in Classroom'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: TabbyColors.brandDarkTeal,
                                side: const BorderSide(
                                    color: TabbyColors.borderMint),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 9),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                ref
                                    .read(classroomTasksProvider.notifier)
                                    .markDone(task.id);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: TabbyColors.brandMintAccent,
                                foregroundColor: TabbyColors.brandDarkTeal,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Mark as Done'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSummary() {
    final courseColor = classroomColorFromHex(task.courseColorHex);
    final stateLabel = switch (task.state) {
      ClassroomTaskState.assigned => classroomTimeRemainingLabel(task),
      ClassroomTaskState.turnedIn => 'Submitted',
      ClassroomTaskState.returned => 'Returned',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: courseColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                task.courseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: courseColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                stateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: classroomUrgencyColor(task.urgency),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: TabbyColors.brandDarkTeal,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          task.dueAt == null
              ? 'No due date'
              : 'Due ${_formatDate(task.dueAt!)}',
          style: const TextStyle(
            color: TabbyColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Task options',
      icon: const Icon(Icons.more_horiz_rounded,
          color: TabbyColors.textSecondary),
      onSelected: (value) {
        if (value == 'open') _openClassroom(context);
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'open',
          enabled: task.classroomLink != null,
          child: const Text('Open in Classroom'),
        ),
      ],
    );
  }

  Future<void> _openClassroom(BuildContext context) async {
    final link = task.classroomLink;
    if (link == null || link.isEmpty) return;
    final launched = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Google Classroom.')),
      );
    }
  }

  String _formatDate(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day at $hour:$minute';
  }
}

class CompactTaskCard extends StatelessWidget {
  const CompactTaskCard({super.key, required this.task});

  final ClassroomTask task;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/tasks'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
        decoration: BoxDecoration(
          color: TabbyColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TabbyColors.borderMint),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 38,
              decoration: BoxDecoration(
                color: classroomUrgencyColor(task.urgency),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.courseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: classroomColorFromHex(task.courseColorHex),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TabbyColors.brandDarkTeal,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              classroomTimeRemainingLabel(task),
              style: TextStyle(
                color: classroomUrgencyColor(task.urgency),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
