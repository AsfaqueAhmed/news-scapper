import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/article_model.dart';

/// CRUD for the `articles` table in Supabase Postgres.
class NewsSupabaseDataSource {
  final SupabaseClient _client;

  NewsSupabaseDataSource(this._client);

  Future<void> upsertArticles(List<ArticleModel> articles) async {
    if (articles.isEmpty) return;
    await _client.from('articles').upsert(articles.map((a) => a.toMap()).toList());
  }

  Future<void> updateArticleEnrichment(
    String id, {
    String? groupId,
    String? category,
  }) async {
    final values = <String, Object?>{};
    if (groupId != null) values['group_id'] = groupId;
    if (category != null) values['category'] = category;
    if (values.isEmpty) return;
    await _client.from('articles').update(values).eq('id', id);
  }

  Future<void> markRead(String id) async {
    await _client.from('articles').update({'is_read': true}).eq('id', id);
  }

  Future<List<ArticleModel>> getArticles({String? sourceId, int limit = 200}) async {
    var query = _client.from('articles').select();
    if (sourceId != null) {
      query = query.eq('source_id', sourceId);
    }
    final rows = await query.order('pub_date', ascending: false).limit(limit);
    return rows.map(ArticleModel.fromMap).toList();
  }

  Future<List<ArticleModel>> getArticlesByGroup(String groupId) async {
    final rows = await _client
        .from('articles')
        .select()
        .eq('group_id', groupId)
        .order('pub_date', ascending: false);
    return rows.map(ArticleModel.fromMap).toList();
  }

  Future<void> pruneOlderThan(Duration age) async {
    final cutoff = DateTime.now().subtract(age).toIso8601String();
    await _client.from('articles').delete().lt('pub_date', cutoff);
  }
}
