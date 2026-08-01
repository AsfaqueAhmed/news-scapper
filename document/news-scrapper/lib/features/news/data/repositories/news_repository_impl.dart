import 'package:uuid/uuid.dart';

import '../../../settings/domain/entities/news_source.dart';
import '../../domain/entities/article.dart';
import '../../domain/entities/cached_news.dart';
import '../../domain/entities/refresh_result.dart';
import '../../domain/repositories/news_repository.dart';
import '../datasources/news_enrichment_data_source.dart';
import '../datasources/news_supabase_data_source.dart';
import '../datasources/news_prefs_data_source.dart';
import '../datasources/news_remote_data_source.dart';
import '../datasources/share_data_source.dart';
import '../models/article_model.dart';

class NewsRepositoryImpl implements NewsRepository {
  final NewsSupabaseDataSource _supabaseDataSource;
  final NewsRemoteDataSource _remoteDataSource;
  final NewsEnrichmentDataSource _enrichmentDataSource;
  final NewsPrefsDataSource _prefsDataSource;
  final ShareDataSource _shareDataSource;

  NewsRepositoryImpl(
    this._supabaseDataSource,
    this._remoteDataSource,
    this._enrichmentDataSource,
    this._prefsDataSource,
    this._shareDataSource,
  );

  @override
  Future<CachedNews> getCachedNews() async {
    final articles = await _supabaseDataSource.getArticles();
    final lastScrapedAt = await _prefsDataSource.getLastScrapedAt();
    final lastShared = await _prefsDataSource.getLastShared();
    return CachedNews(
      articles: articles,
      lastScrapedAt: lastScrapedAt,
      lastShared: lastShared,
    );
  }

  @override
  Future<RefreshResult> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  }) async {
    final errors = <String>[];
    final fetched = <ArticleModel>[];

    for (final source in sources) {
      try {
        fetched.addAll(await _remoteDataSource.fetchSource(source));
      } on RssFetchException catch (e) {
        errors.add('${e.sourceName}: ${e.message}');
      }
    }

    if (fetched.isNotEmpty) {
      await _supabaseDataSource.upsertArticles(fetched);
    }

    if (openRouterToken != null &&
        openRouterToken.isNotEmpty &&
        fetched.isNotEmpty) {
      try {
        final enrichments = await _enrichmentDataSource.enrich(
          fetched,
          openRouterToken,
          runId: const Uuid().v4(),
        );
        for (final e in enrichments) {
          await _supabaseDataSource.updateArticleEnrichment(
            e.articleId,
            category: e.category,
            groupId: e.groupId,
          );
        }
      } on OpenRouterException catch (e) {
        errors.add('AI enrichment: ${e.message}');
      }
    }

    await _supabaseDataSource.pruneOlderThan(const Duration(days: 14));

    final articles = await _supabaseDataSource.getArticles();
    final scrapedAt = DateTime.now();
    await _prefsDataSource.setLastScrapedAt(scrapedAt);

    return RefreshResult(articles: articles, errors: errors, scrapedAt: scrapedAt);
  }

  @override
  Future<void> markRead(String articleId) => _supabaseDataSource.markRead(articleId);

  @override
  Future<void> shareArticle(Article article) async {
    await _shareDataSource.shareArticle(ArticleModel.fromEntity(article));
    await _prefsDataSource.setLastShared(DateTime.now(), article.title);
  }
}
