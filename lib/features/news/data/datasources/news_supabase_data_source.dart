import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/article_model.dart';

/// CRUD for the `articles` table in Supabase Postgres.
class NewsSupabaseDataSource {
  final SupabaseClient _client;

  NewsSupabaseDataSource(this._client);

  /// Excludes `is_read` from the upsert payload: a re-scraped article is
  /// always freshly parsed as unread, and upserting that would silently
  /// clobber a user's "read" state every time the source is re-fetched.
  /// Leaving it out of the payload means new rows still get `false` (the
  /// column default) while existing rows keep whatever `is_read` they had.
  Future<void> upsertArticles(List<ArticleModel> articles) async {
    if (articles.isEmpty) return;
    final rows = articles.map((a) => a.toMap()..remove('is_read')).toList();
    await _client.from('articles').upsert(rows);
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

  /// Latest [perSource] articles from EACH of [sourceIds], merged and
  /// sorted by publish date. Used instead of a single global-cap query so
  /// every enabled source is represented -- a source with fewer/older
  /// articles no longer gets crowded out of the list by higher-volume or
  /// higher-frequency sources.
  Future<List<ArticleModel>> getLatestPerSource(List<String> sourceIds, {int perSource = 6}) async {
    final results = await Future.wait(
      sourceIds.map((id) => getArticles(sourceId: id, limit: perSource)),
    );
    final merged = results.expand((rows) => rows).toList()
      ..sort((a, b) => b.pubDate.compareTo(a.pubDate));
    return merged;
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

  /// Subscribes to the `sync_state` counter that the fetch-batch and
  /// backfill-article-images edge functions bump after a run that
  /// actually changed something. Calls [onChanged] on every update. Not
  /// idempotent -- callers must guard against subscribing more than once
  /// (see `NewsNotifier.startListeningForUpdates`).
  void subscribeToSyncUpdates(void Function() onChanged) {
    _client.channel('sync_state_changes').onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'sync_state',
      callback: (_) => onChanged(),
    ).subscribe();
  }
}
