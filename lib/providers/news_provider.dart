import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/article.dart';
import '../models/news_source.dart';
import '../services/database_service.dart';
import '../services/openrouter_service.dart';
import '../services/rss_service.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';

class NewsProvider extends ChangeNotifier {
  final RssService _rssService;
  final OpenRouterService _openRouterService;
  final ShareService _shareService;

  NewsProvider({
    RssService? rssService,
    OpenRouterService? openRouterService,
    ShareService? shareService,
  })  : _rssService = rssService ?? RssService(),
        _openRouterService = openRouterService ?? OpenRouterService(),
        _shareService = shareService ?? ShareService();

  List<Article> _articles = [];
  DateTime? _lastScrapedAt;
  (DateTime, String)? _lastShared;
  bool _isRefreshing = false;
  final List<String> _lastRunErrors = [];

  List<Article> get articles => List.unmodifiable(_articles);
  DateTime? get lastScrapedAt => _lastScrapedAt;
  (DateTime, String)? get lastShared => _lastShared;
  bool get isRefreshing => _isRefreshing;
  List<String> get lastRunErrors => List.unmodifiable(_lastRunErrors);

  List<Article> articlesForSource(String? sourceId) {
    if (sourceId == null) return articles;
    return _articles.where((a) => a.sourceId == sourceId).toList();
  }

  List<Article> groupSiblings(Article article) {
    if (article.groupId == null) return [article];
    return _articles.where((a) => a.groupId == article.groupId).toList();
  }

  Future<void> loadFromCache() async {
    _articles = await DatabaseService.instance.getArticles();
    _lastScrapedAt = await SettingsService.instance.getLastScrapedAt();
    _lastShared = await SettingsService.instance.getLastShared();
    notifyListeners();
  }

  /// Scrapes every enabled [sources], stores results, and (if [openRouterToken]
  /// is set) asks the LLM to categorize + group same-story articles.
  Future<void> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  }) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _lastRunErrors.clear();
    notifyListeners();

    try {
      final fetched = <Article>[];
      for (final source in sources) {
        try {
          fetched.addAll(await _rssService.fetchSource(source));
        } on RssFetchException catch (e) {
          _lastRunErrors.add('${e.sourceName}: ${e.message}');
        }
      }

      if (fetched.isNotEmpty) {
        await DatabaseService.instance.upsertArticles(fetched);
      }

      if (openRouterToken != null &&
          openRouterToken.isNotEmpty &&
          fetched.isNotEmpty) {
        try {
          final enrichments = await _openRouterService.enrich(
            fetched,
            openRouterToken,
            runId: const Uuid().v4(),
          );
          for (final e in enrichments) {
            await DatabaseService.instance.updateArticleEnrichment(
              e.articleId,
              category: e.category,
              groupId: e.groupId,
            );
          }
        } on OpenRouterException catch (e) {
          _lastRunErrors.add('AI enrichment: ${e.message}');
        }
      }

      await DatabaseService.instance.pruneOlderThan(const Duration(days: 14));

      _articles = await DatabaseService.instance.getArticles();
      _lastScrapedAt = DateTime.now();
      await SettingsService.instance.setLastScrapedAt(_lastScrapedAt!);
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> markRead(Article article) async {
    await DatabaseService.instance.markRead(article.id);
    _articles = [
      for (final a in _articles)
        if (a.id == article.id) a.copyWith(isRead: true) else a,
    ];
    notifyListeners();
  }

  Future<void> shareArticle(Article article) async {
    await _shareService.shareArticle(article);
    _lastShared = (DateTime.now(), article.title);
    notifyListeners();
  }
}
