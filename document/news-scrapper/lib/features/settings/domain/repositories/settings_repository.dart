import '../entities/news_source.dart';

abstract class SettingsRepository {
  Future<List<NewsSource>> getSources();

  Future<void> upsertSource(NewsSource source);

  Future<void> deleteSource(String id);

  Future<String?> getOpenRouterToken();

  Future<void> setOpenRouterToken(String? token);
}
