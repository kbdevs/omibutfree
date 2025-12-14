/// Conversation detail page with full transcript
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/app_provider.dart';

class ConversationDetailPage extends StatefulWidget {
  final Conversation conversation;

  const ConversationDetailPage({super.key, required this.conversation});

  @override
  State<ConversationDetailPage> createState() => _ConversationDetailPageState();
}

class _ConversationDetailPageState extends State<ConversationDetailPage> {
  String _selectedText = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.conversation.title.isNotEmpty ? widget.conversation.title : 'Conversation',
        ),
        actions: [
          if (_selectedText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add selection as memory',
              onPressed: () => _addAsMemory(context),
            ),
        ],
      ),
      body: SelectionArea(
        onSelectionChanged: (selection) {
          setState(() {
            _selectedText = selection?.plainText ?? '';
          });
        },
        contextMenuBuilder: (context, selectableRegionState) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: [
              ...selectableRegionState.contextMenuButtonItems,
              ContextMenuButtonItem(
                label: 'Add as Memory',
                onPressed: () {
                  ContextMenuController.removeAny();
                  _addAsMemory(context);
                },
              ),
            ],
          );
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date and Duration
              Row(
                children: [
                  Text(
                    _formatFullDate(widget.conversation.createdAt),
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                  if (widget.conversation.duration.inSeconds > 0) ...[
                    Text(' • ', style: TextStyle(color: Colors.grey.shade400)),
                    Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 2),
                    Text(
                      widget.conversation.formattedDuration,
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Summary
              if (widget.conversation.summary.isNotEmpty) ...[
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
                  child: Text(widget.conversation.summary),
                ),
                const SizedBox(height: 24),
              ],

              // Transcript
              Row(
                children: [
                  const Text(
                    'Transcript',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Select text to add as memory',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...widget.conversation.segments.map((segment) => _TranscriptRow(segment: segment)),
            ],
          ),
        ),
      ),
    );
  }

  void _addAsMemory(BuildContext context) {
    if (_selectedText.isEmpty) return;
    
    final provider = Provider.of<AppProvider>(context, listen: false);
    provider.addMemory(_selectedText, sourceConversationId: widget.conversation.id);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added memory: "${_selectedText.length > 50 ? '${_selectedText.substring(0, 50)}...' : _selectedText}"'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => Navigator.pop(context), // Go back to see memories tab
        ),
      ),
    );
    
    setState(() => _selectedText = '');
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
