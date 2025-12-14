/// Statistics dashboard page
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/settings_service.dart';


class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final conversations = provider.conversations;
          final memories = provider.memories;
          final tasks = provider.tasks;
          
          // Calculate stats
          final totalConversations = conversations.length;
          final totalMemories = memories.length;
          final totalTasks = tasks.length;
          final completedTasks = tasks.where((t) => t.isCompleted).length;
          
          // Word count across all conversations
          int totalWords = 0;
          Duration totalDuration = Duration.zero;
          for (final conv in conversations) {
            for (final segment in conv.segments) {
              totalWords += segment.text.split(' ').length;
            }
            totalDuration += conv.duration;
          }
          
          // Recent activity (last 7 days)
          final now = DateTime.now();
          final weekAgo = now.subtract(const Duration(days: 7));
          final recentConversations = conversations.where((c) => c.createdAt.isAfter(weekAgo)).length;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              const Text(
                'Your Omi Stats',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Insights from your conversations',
                style: TextStyle(color: Colors.grey.shade400),
              ),
              const SizedBox(height: 24),
              
              // Main stats grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _StatCard(
                    icon: Icons.chat_bubble_outline,
                    label: 'Conversations',
                    value: '$totalConversations',
                    color: const Color(0xFF6C5CE7),
                  ),
                  _StatCard(
                    icon: Icons.psychology_outlined,
                    label: 'Memories',
                    value: '$totalMemories',
                    color: const Color(0xFF00b894),
                  ),
                  _StatCard(
                    icon: Icons.check_circle_outline,
                    label: 'Tasks',
                    value: '$completedTasks / $totalTasks',
                    color: const Color(0xFFfdcb6e),
                  ),
                  _StatCard(
                    icon: Icons.history,
                    label: 'This Week',
                    value: '$recentConversations',
                    color: const Color(0xFF74b9ff),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Detailed stats
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Totals',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _DetailRow(
                        icon: Icons.text_fields,
                        label: 'Words Captured',
                        value: _formatNumber(totalWords),
                      ),
                      const Divider(),
                      _DetailRow(
                        icon: Icons.timer_outlined,
                        label: 'Recording Time',
                        value: _formatDuration(totalDuration),
                      ),
                      const Divider(),
                      _DetailRow(
                        icon: Icons.calendar_today,
                        label: 'First Conversation',
                        value: conversations.isNotEmpty 
                            ? _formatDate(conversations.last.createdAt)
                            : 'N/A',
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Memory categories
              if (memories.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Memory Sources',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        _DetailRow(
                          icon: Icons.auto_awesome,
                          label: 'Auto-extracted',
                          value: '${memories.where((m) => m.category != 'manual').length}',
                        ),
                        const Divider(),
                        _DetailRow(
                          icon: Icons.edit,
                          label: 'Manually Added',
                          value: '${memories.where((m) => m.category == 'manual').length}',
                        ),
                      ],
                    ),
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // API Costs
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'API Costs (Estimated)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              SettingsService.resetUsageStats();
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Usage stats reset')),
                              );
                            },
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(
                        icon: Icons.graphic_eq,
                        label: 'Deepgram (${SettingsService.deepgramMinutesUsed.toStringAsFixed(1)} min)',
                        value: '\$${SettingsService.deepgramCost.toStringAsFixed(4)}',
                      ),
                      const Divider(),
                      _DetailRow(
                        icon: Icons.smart_toy_outlined,
                        label: 'OpenAI (${_formatTokens(SettingsService.openaiInputTokens + SettingsService.openaiOutputTokens)} tokens)',
                        value: '\$${SettingsService.openaiCost.toStringAsFixed(4)}',
                      ),
                      const Divider(),
                      _DetailRow(
                        icon: Icons.attach_money,
                        label: 'Total Estimated',
                        value: '\$${SettingsService.totalApiCost.toStringAsFixed(4)}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Model: ${SettingsService.openaiModel}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Reset All Stats
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => _showResetConfirmation(context),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Reset All Statistics', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Statistics?'),
        content: const Text('This will reset all API usage tracking (Deepgram minutes, OpenAI tokens, and estimated costs). This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              SettingsService.resetUsageStats();
              setState(() {});
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All statistics reset')),
              );
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }

  String _formatNumber(int num) {
    if (num >= 1000000) {
      return '${(num / 1000000).toStringAsFixed(1)}M';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(1)}K';
    }
    return num.toString();
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}s';
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
