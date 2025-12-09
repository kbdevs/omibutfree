/// Conversation detail page with full transcript
import 'package:flutter/material.dart';
import '../models/conversation.dart';

class ConversationDetailPage extends StatelessWidget {
  final Conversation conversation;

  const ConversationDetailPage({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          conversation.title.isNotEmpty ? conversation.title : 'Conversation',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date
            Text(
              _formatFullDate(conversation.createdAt),
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),

            // Summary
            if (conversation.summary.isNotEmpty) ...[
              const Text(
                'Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
                ),
                child: Text(conversation.summary),
              ),
              const SizedBox(height: 24),
            ],

            // Transcript
            const Text(
              'Transcript',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...conversation.segments.map((segment) => _TranscriptRow(segment: segment)),
          ],
        ),
      ),
    );
  }

  String _formatFullDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _TranscriptRow extends StatelessWidget {
  final TranscriptSegment segment;

  const _TranscriptRow({required this.segment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _getSpeakerColor(segment.speakerId),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'S${segment.speakerId}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Speaker ${segment.speakerId}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(segment.text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getSpeakerColor(int speakerId) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    return colors[speakerId % colors.length];
  }
}
