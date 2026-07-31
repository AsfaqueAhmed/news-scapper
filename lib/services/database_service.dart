import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/article.dart';
import '../models/news_source.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'news_scrapper.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sources (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            feedUrl TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE articles (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            link TEXT NOT NULL,
            description TEXT,
            imageUrl TEXT,
            pubDate TEXT NOT NULL,
            sourceId TEXT NOT NULL,
            sourceName TEXT NOT NULL,
            groupId TEXT,
            category TEXT,
            isRead INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_articles_pubDate ON articles(pubDate)');
        await db.execute('CREATE INDEX idx_articles_sourceId ON articles(sourceId)');

        for (final source in NewsSource.defaults) {
          await db.insert('sources', source.toMap());
        }
      },
    );
  }

  // ---- Sources ----

  Future<List<NewsSource>> getSources() async {
    final db = await database;
    final rows = await db.query('sources', orderBy: 'name ASC');
    return rows.map(NewsSource.fromMap).toList();
  }

  Future<void> upsertSource(NewsSource source) async {
    final db = await database;
    await db.insert(
      'sources',
      source.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSource(String id) async {
    final db = await database;
    await db.delete('sources', where: 'id = ?', whereArgs: [id]);
    await db.delete('articles', where: 'sourceId = ?', whereArgs: [id]);
  }

  // ---- Articles ----

  Future<void> upsertArticles(List<Article> articles) async {
    if (articles.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final article in articles) {
      batch.insert(
        'articles',
        article.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateArticleEnrichment(
    String id, {
    String? groupId,
    String? category,
  }) async {
    final db = await database;
    final values = <String, Object?>{};
    if (groupId != null) values['groupId'] = groupId;
    if (category != null) values['category'] = category;
    if (values.isEmpty) return;
    await db.update('articles', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markRead(String id) async {
    final db = await database;
    await db.update(
      'articles',
      {'isRead': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Article>> getArticles({String? sourceId, int limit = 200}) async {
    final db = await database;
    final rows = await db.query(
      'articles',
      where: sourceId != null ? 'sourceId = ?' : null,
      whereArgs: sourceId != null ? [sourceId] : null,
      orderBy: 'pubDate DESC',
      limit: limit,
    );
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getArticlesByGroup(String groupId) async {
    final db = await database;
    final rows = await db.query(
      'articles',
      where: 'groupId = ?',
      whereArgs: [groupId],
      orderBy: 'pubDate DESC',
    );
    return rows.map(Article.fromMap).toList();
  }

  Future<void> pruneOlderThan(Duration age) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(age).toIso8601String();
    await db.delete('articles', where: 'pubDate < ?', whereArgs: [cutoff]);
  }
}
