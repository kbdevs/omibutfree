/// Tasks page - displays extracted tasks from conversations
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/conversation.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          Consumer<AppProvider>(
            builder: (context, provider, _) => provider.tasks.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: provider.loadTasks,
                    tooltip: 'Refresh',
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.tasks.isEmpty) {
            return _buildEmptyState(theme);
          }
          return _buildTasksList(context, provider, theme);
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF6C5CE7).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 48,
                color: Color(0xFF6C5CE7),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Tasks Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tasks from your conversations\nwill appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Try saying "I need to finish my report tonight"',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksList(BuildContext context, AppProvider provider, ThemeData theme) {
    final tasks = provider.tasks;
    final pendingTasks = tasks.where((t) => !t.isCompleted).toList();
    final completedTasks = tasks.where((t) => t.isCompleted).toList();
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pendingTasks.isNotEmpty) ...[
          _buildSectionHeader('Pending', theme, pendingTasks.length),
          ...pendingTasks.map((task) => _buildTaskCard(context, provider, task, theme)),
          const SizedBox(height: 16),
        ],
        if (completedTasks.isNotEmpty) ...[
          _buildSectionHeader('Completed', theme, completedTasks.length),
          ...completedTasks.map((task) => _buildTaskCard(context, provider, task, theme)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF6C5CE7).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6C5CE7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, AppProvider provider, Task task, ThemeData theme) {
    final isOverdue = task.dueDate != null && 
                      task.dueDate!.isBefore(DateTime.now()) && 
                      !task.isCompleted;
    
    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withOpacity(0.2),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      onDismissed: (_) => provider.deleteTask(task.id),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => provider.toggleTaskCompletion(task.id, !task.isCompleted),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox
                GestureDetector(
                  onTap: () => provider.toggleTaskCompletion(task.id, !task.isCompleted),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: task.isCompleted 
                          ? const Color(0xFF6C5CE7) 
                          : Colors.transparent,
                      border: Border.all(
                        color: task.isCompleted 
                            ? const Color(0xFF6C5CE7) 
                            : Colors.grey.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: task.isCompleted
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          decoration: task.isCompleted 
                              ? TextDecoration.lineThrough 
                              : null,
                          color: task.isCompleted 
                              ? theme.colorScheme.onSurface.withOpacity(0.4) 
                              : null,
                        ),
                      ),
                      if (task.dueDate != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: isOverdue 
                                  ? Colors.red 
                                  : theme.colorScheme.onSurface.withOpacity(0.4),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDueDate(task.dueDate!),
                              style: TextStyle(
                                fontSize: 12,
                                color: isOverdue 
                                    ? Colors.red 
                                    : theme.colorScheme.onSurface.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                  onPressed: () => _confirmDelete(context, provider, task.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final taskDate = DateTime(date.year, date.month, date.day);
    
    String dayPart;
    if (taskDate == today) {
      dayPart = 'Today';
    } else if (taskDate == tomorrow) {
      dayPart = 'Tomorrow';
    } else if (date.difference(now).inDays < 7) {
      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      dayPart = weekdays[date.weekday - 1];
    } else {
      dayPart = '${date.month}/${date.day}';
    }
    
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    final timePart = '$hour:${date.minute.toString().padLeft(2, '0')} $amPm';
    
    return '$dayPart at $timePart';
  }

  void _confirmDelete(BuildContext context, AppProvider provider, String taskId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteTask(taskId);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
