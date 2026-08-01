import '../../domain/entities/news_source.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/secure_token_data_source.dart';
import '../datasources/settings_supabase_data_source.dart';
import '../models/news_source_model.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsSupabaseDataSource _supabaseDataSource;
  final SecureTokenDataSource _secureTokenDataSource;

  SettingsRepositoryImpl(this._supabaseDataSource, this._secureTokenDataSource);

  @override
  Future<List<NewsSource>> getSources() => _supabaseDataSource.getSources();

  @override
  Future<void> upsertSource(NewsSource source) =>
      _supabaseDataSource.upsertSource(NewsSourceModel.fromEntity(source));

  @override
  Future<void> deleteSource(String id) => _supabaseDataSource.deleteSource(id);

  @override
  Future<String?> getOpenRouterToken() =>
      _secureTokenDataSource.getOpenRouterToken();

  @override
  Future<void> setOpenRouterToken(String? token) =>
      _secureTokenDataSource.setOpenRouterToken(token);
}
