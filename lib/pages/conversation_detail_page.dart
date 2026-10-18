/// Conversation detail page with full transcript
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';

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
              const SizedBox(height: 4),
              Text(
                SettingsService.speakerIdEnabled
                    ? 'Tap a speaker to name them - the app learns their voice'
                    : 'Tap a speaker to name them',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              ...widget.conversation.segments.map(
                (segment) => _TranscriptRow(
                  segment: segment,
                  onSpeakerTap: () => _showSpeakerSheet(segment.speakerId),
                ),
              ),
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

  Future<void> _showSpeakerSheet(int speakerId) async {
    final conversation = widget.conversation;
    final segments =
        conversation.segments.where((s) => s.speakerId == speakerId).toList();
    if (segments.isEmpty) return;
    final current = segments.first;

    final choice = await showModalBottomSheet<_SpeakerChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SpeakerSheet(
        currentName: current.displayName,
        currentPersonId: current.personId,
        sampleText: segments.first.text,
      ),
    );
    if (choice == null || !mounted) return;

    final provider = Provider.of<AppProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    if (choice.clear) {
      await provider.clearSpeakerLabel(
        conversation: conversation,
        speakerId: speakerId,
      );
      if (mounted) setState(() {});
      return;
    }

    final learned = await provider.assignSpeaker(
      conversation: conversation,
      speakerId: speakerId,
      personId: choice.personId,
      newPersonName: choice.newName,
    );
    if (!mounted) return;
    setState(() {});
    final name = conversation.segments
        .firstWhere((s) => s.speakerId == speakerId)
        .displayName;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          learned > 0
              ? 'Labeled as $name - learned from $learned voice sample${learned == 1 ? '' : 's'}'
              : SettingsService.speakerIdEnabled
                  ? 'Labeled as $name. No voice sample is stored for this '
                      'speaker (too little speech, recognition was off, or the '
                      'samples were deleted after '
                      '${DatabaseService.voiceClipRetentionDays} days), so '
                      'the app could not learn their voice from it.'
                  : 'Labeled as $name. To let the app learn voices from '
                      'future conversations, turn on "Recognize speakers" in '
                      'Settings.',
        ),
        duration: const Duration(seconds: 5),
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
  final VoidCallback onSpeakerTap;

  const _TranscriptRow({required this.segment, required this.onSpeakerTap});

  @override
  Widget build(BuildContext context) {
    final named = segment.speakerName != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A button for screen readers, with a 48 dp touch target around the
          // 32 dp avatar.
          Semantics(
            button: true,
            excludeSemantics: true,
            label: named
                ? 'Change speaker ${segment.speakerName}'
                : 'Name speaker ${segment.speakerId}',
            child: InkWell(
              onTap: onSpeakerTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _getSpeakerColor(segment.speakerId),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        named
                            ? segment.speakerName!.characters.first.toUpperCase()
                            : 'S${segment.speakerId}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Same action as the avatar button, so hidden from screen readers.
                ExcludeSemantics(
                  child: InkWell(
                    onTap: onSpeakerTap,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(
                        segment.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: named ? Colors.white : Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
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

/// What the user picked in the speaker sheet.
class _SpeakerChoice {
  final String? personId; // existing person
  final String? newName; // or a new person
  final bool clear; // or remove the label

  const _SpeakerChoice.person(this.personId)
      : newName = null,
        clear = false;
  const _SpeakerChoice.newPerson(this.newName)
      : personId = null,
        clear = false;
  const _SpeakerChoice.clear()
      : personId = null,
        newName = null,
        clear = true;
}

class _SpeakerSheet extends StatelessWidget {
  final String currentName;
  final String? currentPersonId;
  final String sampleText;

  const _SpeakerSheet({
    required this.currentName,
    required this.currentPersonId,
    required this.sampleText,
  });

  @override
  Widget build(BuildContext context) {
    final people = Provider.of<AppProvider>(context).people;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'Who is $currentName?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '"$sampleText"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in people)
                    ListTile(
                      leading: CircleAvatar(
                        child: Text(p.name.characters.first.toUpperCase()),
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                        p.sampleCount == 0
                            ? 'No voice samples yet'
                            : '${p.sampleCount} voice sample${p.sampleCount == 1 ? '' : 's'}',
                      ),
                      trailing: p.id == currentPersonId
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () =>
                          Navigator.pop(context, _SpeakerChoice.person(p.id)),
                    ),
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add)),
                    title: const Text('New person...'),
                    onTap: () async {
                      final name = await showDialog<String>(
                        context: context,
                        builder: (_) => const _NameDialog(),
                      );
                      if (name != null && name.trim().isNotEmpty) {
                        if (context.mounted) {
                          Navigator.pop(context, _SpeakerChoice.newPerson(name));
                        }
                      }
                    },
                  ),
                  if (currentPersonId != null)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.close)),
                      title: const Text('Remove label'),
                      onTap: () =>
                          Navigator.pop(context, const _SpeakerChoice.clear()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New person'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Name'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
