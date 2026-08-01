import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../settings/domain/entities/news_source.dart';
import '../../data/share/share_card_renderer.dart';
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

  /// Downloads (and caches) the article's source image for the share
  /// preview editor.
  Future<ui.Image?> loadShareImage(Article article);

  /// Renders the share card -- photo + title overlay per [config] -- as
  /// PNG bytes, without sharing it yet.
  Future<Uint8List> composeShareCard(Article article, ui.Image? image, ShareCardConfig config);

  /// Opens the native share sheet with the already-composed [pngBytes] and
  /// records the share.
  Future<void> shareComposedCard(Article article, Uint8List pngBytes);
}
