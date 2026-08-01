import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/news_source_model.dart';

/// CRUD for the `sources` table in Supabase Postgres.
class SettingsSupabaseDataSource {
  final SupabaseClient _client;

  SettingsSupabaseDataSource(this._client);

  Future<List<NewsSourceModel>> getSources() async {
    final rows = await _client.from('sources').select().order('name');
    return rows.map(NewsSourceModel.fromMap).toList();
  }

  Future<void> upsertSource(NewsSourceModel source) async {
    await _client.from('sources').upsert(source.toMap());
  }

  Future<void> deleteSource(String id) async {
    // Postgres FK `articles.source_id -> sources.id ON DELETE CASCADE`
    // handles removing the source's articles.
    await _client.from('sources').delete().eq('id', id);
  }
}
