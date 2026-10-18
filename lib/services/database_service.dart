/// SQLite database service for local storage
import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/conversation.dart';

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'omi_local.db';
  static const int _dbVersion = 4; // v4: speaker recognition tables

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

        await _createSpeakerTables(db);
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
        if (oldVersion < 4) {
          await _createSpeakerTables(db);
        }
      },
    );
  }

  /// Tables for speaker recognition (added in schema v4).
  static Future<void> _createSpeakerTables(Database db) async {
    // People whose voices have been enrolled.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS people (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // Voice samples (embeddings) for each person. `embedding` is a raw
    // little-endian float32 vector. source_* records which conversation
    // speaker it was learned from so a wrong label can be undone.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS person_embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id TEXT NOT NULL,
        embedding BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        source_conversation_id TEXT,
        source_speaker_id INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_person_embeddings_person ON person_embeddings(person_id)',
    );

    // Voice samples captured for each diarized speaker of a conversation, kept
    // so the user can label that speaker later. `embeddings` holds `count`
    // float32 vectors back to back.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_speakers (
        conversation_id TEXT NOT NULL,
        speaker_id INTEGER NOT NULL,
        embeddings BLOB NOT NULL,
        count INTEGER NOT NULL,
        PRIMARY KEY (conversation_id, speaker_id)
      )
    ''');
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
    final conversations = rows.map((row) => Conversation.fromDbRow(row)).toList();
    await _applyPersonNames(db, conversations);
    return conversations;
  }

  /// Transcript segments store the name a person had when they were labeled.
  /// Look the current name up by person id, so a rename shows everywhere
  /// (including exports) without rewriting every conversation.
  static Future<void> _applyPersonNames(
    Database db,
    List<Conversation> conversations,
  ) async {
    final rows = await db.query('people', columns: ['id', 'name']);
    if (rows.isEmpty) return;
    applyPersonNames(conversations, {
      for (final r in rows) r['id'] as String: r['name'] as String,
    });
  }

  static Future<Conversation?> getConversation(String id) async {
    final db = await database;
    final rows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    final conversation = Conversation.fromDbRow(rows.first);
    await _applyPersonNames(db, [conversation]);
    return conversation;
  }

  static Future<void> deleteConversation(String id) async {
    final db = await database;
    // One transaction: if the app stopped between the two deletes, the voice
    // samples would be left without a conversation and the retention cleanup
    // (which looks them up through their conversation) would never remove them.
    await db.transaction((txn) async {
      await txn.delete('conversations', where: 'id = ?', whereArgs: [id]);
      await txn.delete(
        'conversation_speakers',
        where: 'conversation_id = ?',
        whereArgs: [id],
      );
    });
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

  // Speaker recognition (people, voice samples)

  /// Max voice samples kept per person; the oldest are dropped first.
  static const int maxEmbeddingsPerPerson = 40;

  static Uint8List _floatsToBlob(List<Float32List> vectors) {
    final total = vectors.fold<int>(0, (n, v) => n + v.length);
    final out = Float32List(total);
    int offset = 0;
    for (final v in vectors) {
      out.setAll(offset, v);
      offset += v.length;
    }
    return out.buffer.asUint8List();
  }

  /// Split a flat float32 blob into [count] vectors.
  static List<Float32List> _blobToFloats(Uint8List blob, int count) {
    if (count <= 0 || blob.isEmpty) return [];
    // Copy so the buffer is 4-byte aligned regardless of how sqflite sliced it.
    final aligned = Uint8List.fromList(blob).buffer.asFloat32List();
    final dim = aligned.length ~/ count;
    return [
      for (int i = 0; i < count; i++)
        Float32List.fromList(aligned.sublist(i * dim, (i + 1) * dim)),
    ];
  }

  static Future<List<Person>> getPeople() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.created_at,
             (SELECT COUNT(*) FROM person_embeddings e WHERE e.person_id = p.id) AS sample_count
      FROM people p
      ORDER BY p.name COLLATE NOCASE
    ''');
    return rows.map((r) => Person.fromDbRow(r)).toList();
  }

  /// All voice samples grouped by person id.
  static Future<Map<String, List<Float32List>>> getAllPersonEmbeddings() async {
    final db = await database;
    final rows = await db.query('person_embeddings', orderBy: 'id ASC');
    final result = <String, List<Float32List>>{};
    for (final r in rows) {
      final vectors = _blobToFloats(r['embedding'] as Uint8List, 1);
      if (vectors.isEmpty) continue;
      result.putIfAbsent(r['person_id'] as String, () => []).add(vectors.first);
    }
    return result;
  }

  static Future<void> savePerson(String id, String name) async {
    final db = await database;
    await db.insert(
      'people',
      {
        'id': id,
        'name': name,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> renamePerson(String id, String name) async {
    final db = await database;
    await db.update('people', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes the person and all of their voice samples, including the samples
  /// kept for labeling the speakers named as them in past conversations.
  /// Transcript segments that were labeled with their name keep the text
  /// label. (Samples of a speaker that was never named stay until they expire.)
  static Future<void> deletePerson(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'conversations',
        columns: ['id', 'transcript'],
        where: 'transcript LIKE ?',
        whereArgs: ['%$id%'],
      );
      for (final row in rows) {
        final transcript = row['transcript'] as String?;
        if (transcript == null || transcript.isEmpty) continue;
        final speakers = <int>{};
        for (final s in jsonDecode(transcript) as List) {
          if (s is Map && s['person_id'] == id && s['speaker_id'] is num) {
            speakers.add((s['speaker_id'] as num).toInt());
          }
        }
        for (final speaker in speakers) {
          await txn.delete(
            'conversation_speakers',
            where: 'conversation_id = ? AND speaker_id = ?',
            whereArgs: [row['id'], speaker],
          );
        }
      }
      await txn.delete('person_embeddings', where: 'person_id = ?', whereArgs: [id]);
      await txn.delete('people', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// How long the voice samples kept for labeling a conversation's speakers
  /// are retained. Samples copied to a named person are kept until deleted.
  static const int voiceClipRetentionDays = 14;

  /// Deletes the labeling samples of conversations older than [days]. Returns
  /// how many rows were removed.
  static Future<int> purgeOldConversationSpeakers({
    int days = voiceClipRetentionDays,
    DateTime? now,
  }) async {
    final db = await database;
    final cutoff = (now ?? DateTime.now())
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return db.rawDelete(
      'DELETE FROM conversation_speakers WHERE conversation_id IN '
      '(SELECT id FROM conversations WHERE created_at < ?)',
      [cutoff],
    );
  }

  /// Deletes every stored voice sample (named people's and per-conversation).
  /// People keep their names.
  static Future<void> deleteAllVoiceData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('conversation_speakers');
      await txn.delete('person_embeddings');
    });
  }

  /// Remove voice samples previously learned from this conversation speaker
  /// (used before re-labeling so a wrong label does not keep polluting the
  /// wrong person's profile).
  static Future<void> removeEnrollmentsFor(
    String conversationId,
    int speakerId,
  ) async {
    final db = await database;
    await db.delete(
      'person_embeddings',
      where: 'source_conversation_id = ? AND source_speaker_id = ?',
      whereArgs: [conversationId, speakerId],
    );
  }

  /// Add voice samples to a person, then trim to [maxEmbeddingsPerPerson].
  static Future<void> addPersonEmbeddings(
    String personId,
    List<Float32List> embeddings, {
    String? conversationId,
    int? speakerId,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final e in embeddings) {
      batch.insert('person_embeddings', {
        'person_id': personId,
        'embedding': _floatsToBlob([e]),
        'created_at': now,
        'source_conversation_id': conversationId,
        'source_speaker_id': speakerId,
      });
    }
    await batch.commit(noResult: true);

    await db.rawDelete(
      '''
      DELETE FROM person_embeddings
      WHERE person_id = ?1 AND id NOT IN (
        SELECT id FROM person_embeddings WHERE person_id = ?1
        ORDER BY id DESC LIMIT ?2
      )
      ''',
      [personId, maxEmbeddingsPerPerson],
    );
  }

  /// Persist the voice samples gathered for each diarized speaker of a
  /// conversation so they can be labeled later.
  static Future<void> saveConversationSpeakers(
    String conversationId,
    Map<int, List<Float32List>> embeddingsBySpeaker,
  ) async {
    if (embeddingsBySpeaker.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final entry in embeddingsBySpeaker.entries) {
      if (entry.value.isEmpty) continue;
      batch.insert(
        'conversation_speakers',
        {
          'conversation_id': conversationId,
          'speaker_id': entry.key,
          'embeddings': _floatsToBlob(entry.value),
          'count': entry.value.length,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Float32List>> getConversationSpeakerEmbeddings(
    String conversationId,
    int speakerId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'conversation_speakers',
      where: 'conversation_id = ? AND speaker_id = ?',
      whereArgs: [conversationId, speakerId],
    );
    if (rows.isEmpty) return [];
    return _blobToFloats(
      rows.first['embeddings'] as Uint8List,
      rows.first['count'] as int,
    );
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
    final people = await getPeople();

    return {
      'export_date': DateTime.now().toIso8601String(),
      'app_version': '2.1.0',
      'conversations': conversations.map((c) => c.toJson()).toList(),
      'memories': memories.map((m) => m.toJson()).toList(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
      // Names of labeled people, so `person_id` in the transcripts resolves.
      // Voice samples (voiceprints) are deliberately not exported.
      'people': [
        for (final p in people)
          {
            'id': p.id,
            'name': p.name,
            'created_at': p.createdAt.millisecondsSinceEpoch,
          },
      ],
    };
  }
}
