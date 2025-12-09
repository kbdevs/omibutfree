/// SQLite database service for local storage
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/conversation.dart';

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'omi_local.db';
  static const int _dbVersion = 1;

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
}
