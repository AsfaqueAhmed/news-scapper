import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../settings/domain/entities/news_source.dart';
import '../../data/share/share_card_renderer.dart';
import '../entities/article.dart';
import '../entities/cached_news.dart';
import '../entities/refresh_result.dart';

abstract class NewsRepository {
  /// Reads current cached articles: the latest few per each of [sources],
  /// not a single global-cap query -- see
  /// `NewsSupabaseDataSource.getLatestPerSource` docs for why.
  Future<CachedNews> getCachedNews({required List<NewsSource> sources});

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

  /// Subscribes to backend sync updates; [onChanged] is called whenever
  /// the server-side cron jobs successfully change something, so the
  /// caller can reload without the user pulling to refresh.
  void subscribeToUpdates(void Function() onChanged);
}
