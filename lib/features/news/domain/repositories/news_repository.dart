import '../../../settings/domain/entities/news_source.dart';
import '../entities/article.dart';
import '../entities/cached_news.dart';
import '../entities/refresh_result.dart';

abstract class NewsRepository {
  Future<CachedNews> getCachedNews();

  /// Scrapes every enabled [sources], stores results, and (if
  /// [openRouterToken] is set) asks the LLM to categorize + group
  /// same-story articles.
  Future<RefreshResult> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  });

  Future<void> markRead(String articleId);

  Future<void> shareArticle(Article article);
}
