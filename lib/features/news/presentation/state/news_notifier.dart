import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/news_source.dart';
import '../../data/share/share_card_renderer.dart';
import '../../domain/entities/article.dart';
import '../../domain/usecases/compose_share_card_usecase.dart';
import '../../domain/usecases/get_cached_articles_usecase.dart';
import '../../domain/usecases/group_siblings_usecase.dart';
import '../../domain/usecases/load_share_image_usecase.dart';
import '../../domain/usecases/mark_article_read_usecase.dart';
import '../../domain/usecases/refresh_articles_usecase.dart';
import '../../domain/usecases/share_composed_card_usecase.dart';
import 'news_providers.dart';
import 'news_state.dart';

class NewsNotifier extends Notifier<NewsState> {
  late final GetCachedArticlesUseCase _getCachedArticles;
  late final RefreshArticlesUseCase _refreshArticles;
  late final MarkArticleReadUseCase _markArticleRead;
  late final LoadShareImageUseCase _loadShareImage;
  late final ComposeShareCardUseCase _composeShareCard;
  late final ShareComposedCardUseCase _shareComposedCard;
  late final GroupSiblingsUseCase _groupSiblings;

  @override
  NewsState build() {
    _getCachedArticles = ref.watch(getCachedArticlesUseCaseProvider);
    _refreshArticles = ref.watch(refreshArticlesUseCaseProvider);
    _markArticleRead = ref.watch(markArticleReadUseCaseProvider);
    _loadShareImage = ref.watch(loadShareImageUseCaseProvider);
    _composeShareCard = ref.watch(composeShareCardUseCaseProvider);
    _shareComposedCard = ref.watch(shareComposedCardUseCaseProvider);
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

  Future<ui.Image?> loadShareImage(Article article) => _loadShareImage(article);

  Future<Uint8List> composeShareCard(Article article, ui.Image? image, ShareCardConfig config) =>
      _composeShareCard(article, image, config);

  Future<void> shareComposedCard(Article article, Uint8List pngBytes) async {
    await _shareComposedCard(article, pngBytes);
    state = state.copyWith(lastShared: (DateTime.now(), article.title));
  }
}
