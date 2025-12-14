/// SQLite database service for local storage
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/conversation.dart';

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'omi_local.db';
  static const int _dbVersion = 3; // Incremented for tasks table

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            title TEXT,
            summary TEXT,
            transcript TEXT
          )
        ''');
        
        await db.execute('''
          CREATE TABLE chat_messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT,
            text TEXT NOT NULL,
            is_user INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE memories (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            category TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            source_conversation_id TEXT
          )
        ''');
        
        await db.execute('''
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            due_date INTEGER,
            created_at INTEGER NOT NULL,
            source_conversation_id TEXT,
            is_completed INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS memories (
              id TEXT PRIMARY KEY,
              content TEXT NOT NULL,
              category TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              source_conversation_id TEXT
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS tasks (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              description TEXT,
              due_date INTEGER,
              created_at INTEGER NOT NULL,
              source_conversation_id TEXT,
              is_completed INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
      },
    );
  }

  // Conversation CRUD operations

  static Future<void> saveConversation(Conversation conversation) async {
    final db = await database;
    await db.insert(
      'conversations',
      {
        'id': conversation.id,
        'created_at': conversation.createdAt.millisecondsSinceEpoch,
        'title': conversation.title,
        'summary': conversation.summary,
        'transcript': jsonEncode(conversation.segments.map((s) => s.toJson()).toList()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Conversation>> getConversations({int limit = 50}) async {
    final db = await database;
    final rows = await db.query(
      'conversations',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((row) => Conversation.fromDbRow(row)).toList();
  }

  static Future<Conversation?> getConversation(String id) async {
    final db = await database;
    final rows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Conversation.fromDbRow(rows.first);
  }

  static Future<void> deleteConversation(String id) async {
    final db = await database;
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  static Future<String> getAllConversationsContext({int limit = 10}) async {
    final conversations = await getConversations(limit: limit);
    if (conversations.isEmpty) return '';
    
    return conversations.map((c) {
      return '''
--- Conversation from ${c.createdAt.toLocal()} ---
Title: ${c.title}
Summary: ${c.summary}
Transcript:
${c.transcript}
''';
    }).join('\n\n');
  }

  // Memory CRUD operations

  static Future<void> saveMemory(Memory memory) async {
    final db = await database;
    await db.insert(
      'memories',
      {
        'id': memory.id,
        'content': memory.content,
        'category': memory.category,
        'created_at': memory.createdAt.millisecondsSinceEpoch,
        'source_conversation_id': memory.sourceConversationId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Memory>> getMemories({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'memories',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((row) => Memory.fromDbRow(row)).toList();
  }

  static Future<void> deleteMemory(String id) async {
    final db = await database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  /// Update memory content
  static Future<void> updateMemory(String id, String content) async {
    final db = await database;
    await db.update(
      'memories',
      {'content': content},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Check if a similar memory already exists (for deduplication)
  static Future<bool> hasSimilarMemory(String content) async {
    final db = await database;
    final normalizedContent = content.toLowerCase().trim();
    
    final rows = await db.query('memories');
    for (final row in rows) {
      final existingContent = (row['content'] as String).toLowerCase().trim();
      // Check for high similarity (simple substring or exact match)
      if (existingContent == normalizedContent || 
          existingContent.contains(normalizedContent) ||
          normalizedContent.contains(existingContent)) {
        return true;
      }
    }
    return false;
  }

  // Task CRUD operations

  static Future<void> saveTask(Task task) async {
    final db = await database;
    await db.insert(
      'tasks',
      {
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'due_date': task.dueDate?.millisecondsSinceEpoch,
        'created_at': task.createdAt.millisecondsSinceEpoch,
        'source_conversation_id': task.sourceConversationId,
        'is_completed': task.isCompleted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Task>> getTasks({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      orderBy: 'is_completed ASC, due_date ASC, created_at DESC',
      limit: limit,
    );
    return rows.map((row) => Task.fromDbRow(row)).toList();
  }

  static Future<void> updateTaskCompletion(String id, bool isCompleted) async {
    final db = await database;
    await db.update(
      'tasks',
      {'is_completed': isCompleted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  /// Check if a similar task already exists (for deduplication)
  static Future<bool> hasSimilarTask(String title) async {
    final db = await database;
    final normalizedTitle = title.toLowerCase().trim();
    
    final rows = await db.query('tasks', where: 'is_completed = 0');
    for (final row in rows) {
      final existingTitle = (row['title'] as String).toLowerCase().trim();
      if (existingTitle == normalizedTitle || 
          existingTitle.contains(normalizedTitle) ||
          normalizedTitle.contains(existingTitle)) {
        return true;
      }
    }
    return false;
  }

  /// Export all data for backup/sharing
  static Future<Map<String, dynamic>> exportAllData() async {
    final conversations = await getConversations(limit: 10000);
    final memories = await getMemories(limit: 10000);
    final tasks = await getTasks(limit: 10000);
    
    return {
      'export_date': DateTime.now().toIso8601String(),
      'app_version': '2.1.0',
      'conversations': conversations.map((c) => c.toJson()).toList(),
      'memories': memories.map((m) => m.toJson()).toList(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
    };
  }
}
