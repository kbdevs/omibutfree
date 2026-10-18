// Manage the people whose voices the app can recognize.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context);
    final people = provider.people;

    return Scaffold(
      appBar: AppBar(
        title: const Text('People & Voices'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (action) async {
              if (action == 'delete_all') {
                final ok = await _confirmDeleteAll(context);
                if (ok == true) await provider.deleteAllVoiceData();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete_all',
                child: Text('Delete all voice data'),
              ),
            ],
          ),
        ],
      ),
      body: people.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No one yet.\n\nOpen a conversation and tap a speaker to name '
                  'them. The app learns each person\'s voice from the clips '
                  'you label and recognizes them in future conversations.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
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
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'rename') {
                          final name = await _askName(context, p.name);
                          if (name != null && name.trim().isNotEmpty) {
                            final renamed = await provider.renamePerson(p.id, name);
                            if (!renamed && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Someone called "${name.trim()}" already exists. '
                                    'Delete or rename that person first.',
                                  ),
                                ),
                              );
                            }
                          }
                        } else if (action == 'delete') {
                          final ok = await _confirmDelete(context, p.name);
                          if (ok == true) await provider.deletePerson(p.id);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete voice & person'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Future<String?> _askName(BuildContext context, String current) {
    return showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: current),
    );
  }

  Future<bool?> _confirmDeleteAll(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all voice data?'),
        content: const Text(
          'Every saved voice sample is deleted: those learned for the people '
          'listed here and those kept for naming speakers in past '
          'conversations. People keep their names but will not be recognized '
          'again until you name them in new conversations, because the '
          'samples from past conversations are gone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text(
          'Their saved voice samples are deleted, including those kept for '
          'speakers named as them in past conversations, so they will no '
          'longer be recognized. Names already shown in past transcripts stay '
          'as text. Samples of speakers you never named are kept until they '
          'expire; "Delete all voice data" removes those too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String initial;
  const _RenameDialog({required this.initial});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
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
