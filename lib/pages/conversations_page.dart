/// Conversations history page with multi-select deletion
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/conversation.dart';
import 'conversation_detail_page.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  bool _isSelectionMode = false;
  bool _isSearching = false;
  final Set<String> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      
      // Exit selection mode if nothing selected
      if (_selectedIds.isEmpty && _isSelectionMode) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAll(List<Conversation> conversations) {
    setState(() {
      _selectedIds.addAll(conversations.map((c) => c.id));
    });
  }

  Future<void> _deleteSelected(BuildContext context) async {
    if (_selectedIds.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversations'),
        content: Text('Delete ${_selectedIds.length} conversation${_selectedIds.length > 1 ? 's' : ''}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final provider = context.read<AppProvider>();
      for (final id in _selectedIds) {
        await provider.deleteConversation(id);
      }
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Conversation> _filterConversations(List<Conversation> conversations) {
    if (_searchQuery.isEmpty) return conversations;
    final query = _searchQuery.toLowerCase();
    return conversations.where((c) {
      return c.title.toLowerCase().contains(query) ||
             c.summary.toLowerCase().contains(query) ||
             c.transcript.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search conversations...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (value) => setState(() => _searchQuery = value),
            )
          : Text(_isSelectionMode 
              ? '${_selectedIds.length} selected' 
              : 'Conversations'),
        actions: [
          if (_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel Search',
              onPressed: () => setState(() {
                _isSearching = false;
                _searchQuery = '';
                _searchController.clear();
              }),
            ),
          ] else if (_isSelectionMode) ...[
            Consumer<AppProvider>(
              builder: (context, provider, _) => IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select All',
                onPressed: () => _selectAll(provider.conversations),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete Selected',
              onPressed: _selectedIds.isNotEmpty 
                ? () => _deleteSelected(context) 
                : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: _toggleSelectionMode,
            ),
          ] else ...[
            Consumer<AppProvider>(
              builder: (context, provider, _) {
                if (provider.conversations.isEmpty) return const SizedBox();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Search',
                      onPressed: () => setState(() => _isSearching = true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.checklist),
                      tooltip: 'Select',
                      onPressed: _toggleSelectionMode,
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.conversations.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start recording to create your first conversation',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final filteredConversations = _filterConversations(provider.conversations);
          
          if (filteredConversations.isEmpty && _searchQuery.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No results for "$_searchQuery"',
                    style: const TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.loadConversations,
            child: ListView.builder(
              itemCount: filteredConversations.length,
              itemBuilder: (context, index) {
                final conversation = filteredConversations[index];
                final isSelected = _selectedIds.contains(conversation.id);
                
                return _ConversationTile(
                  conversation: conversation,
                  isSelectionMode: _isSelectionMode,
                  isSelected: isSelected,
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(conversation.id);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConversationDetailPage(conversation: conversation),
                        ),
                      );
                    }
                  },
                  onLongPress: () {
                    if (!_isSelectionMode) {
                      _toggleSelectionMode();
                      _toggleSelection(conversation.id);
                    }
                  },
                  onDelete: () {
                    provider.deleteConversation(conversation.id);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: isSelectionMode 
        ? Checkbox(
            value: isSelected,
            onChanged: (_) => onTap(),
          )
        : null,
      title: Text(
        conversation.title.isNotEmpty ? conversation.title : 'Untitled',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conversation.summary.isNotEmpty)
            Text(
              conversation.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade400),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _formatDate(conversation.createdAt),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
              if (conversation.duration.inSeconds > 0) ...[
                Text(
                  ' • ',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                Icon(Icons.timer_outlined, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 2),
                Text(
                  conversation.formattedDuration,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: isSelectionMode ? null : const Icon(Icons.chevron_right),
      selected: isSelected,
      selectedTileColor: Colors.deepPurple.withOpacity(0.1),
      onTap: onTap,
      onLongPress: onLongPress,
    );

    if (isSelectionMode) {
      return tile;
    }

    return Dismissible(
      key: Key(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: tile,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
