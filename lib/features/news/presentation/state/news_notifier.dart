import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/news_source.dart';
import '../../domain/entities/article.dart';
import '../../domain/usecases/get_cached_articles_usecase.dart';
import '../../domain/usecases/group_siblings_usecase.dart';
import '../../domain/usecases/mark_article_read_usecase.dart';
import '../../domain/usecases/refresh_articles_usecase.dart';
import '../../domain/usecases/share_article_usecase.dart';
import 'news_providers.dart';
import 'news_state.dart';

class NewsNotifier extends Notifier<NewsState> {
  late final GetCachedArticlesUseCase _getCachedArticles;
  late final RefreshArticlesUseCase _refreshArticles;
  late final MarkArticleReadUseCase _markArticleRead;
  late final ShareArticleUseCase _shareArticle;
  late final GroupSiblingsUseCase _groupSiblings;

  @override
  NewsState build() {
    _getCachedArticles = ref.watch(getCachedArticlesUseCaseProvider);
    _refreshArticles = ref.watch(refreshArticlesUseCaseProvider);
    _markArticleRead = ref.watch(markArticleReadUseCaseProvider);
    _shareArticle = ref.watch(shareArticleUseCaseProvider);
    _groupSiblings = ref.watch(groupSiblingsUseCaseProvider);
    return const NewsState();
  }

  List<Article> groupSiblings(Article article) =>
      _groupSiblings(state.articles, article);

  Future<void> loadFromCache() async {
    final cached = await _getCachedArticles();
    state = state.copyWith(
      articles: cached.articles,
      lastScrapedAt: cached.lastScrapedAt,
      lastShared: cached.lastShared,
    );
  }

  Future<void> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  }) async {
    if (state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, lastRunErrors: []);

    try {
      final result = await _refreshArticles(
        sources: sources,
        openRouterToken: openRouterToken,
      );
      state = state.copyWith(
        articles: result.articles,
        lastScrapedAt: result.scrapedAt,
        lastRunErrors: result.errors,
      );
    } finally {
      state = state.copyWith(isRefreshing: false);
    }
  }

  Future<void> markRead(Article article) async {
    await _markArticleRead(article.id);
    state = state.copyWith(
      articles: [
        for (final a in state.articles)
          if (a.id == article.id) a.copyWith(isRead: true) else a,
      ],
    );
  }

  Future<void> shareArticle(Article article) async {
    await _shareArticle(article);
    state = state.copyWith(lastShared: (DateTime.now(), article.title));
  }
}
