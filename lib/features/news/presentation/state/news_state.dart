import '../../domain/entities/article.dart';

class NewsState {
  final List<Article> articles;
  final DateTime? lastScrapedAt;
  final (DateTime, String)? lastShared;
  final bool isRefreshing;
  final List<String> lastRunErrors;

  const NewsState({
    this.articles = const [],
    this.lastScrapedAt,
    this.lastShared,
    this.isRefreshing = false,
    this.lastRunErrors = const [],
  });

  List<Article> articlesForSource(String? sourceId) {
    if (sourceId == null) return articles;
    return articles.where((a) => a.sourceId == sourceId).toList();
  }

  NewsState copyWith({
    List<Article>? articles,
    DateTime? lastScrapedAt,
    (DateTime, String)? lastShared,
    bool? isRefreshing,
    List<String>? lastRunErrors,
  }) {
    return NewsState(
      articles: articles ?? this.articles,
      lastScrapedAt: lastScrapedAt ?? this.lastScrapedAt,
      lastShared: lastShared ?? this.lastShared,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastRunErrors: lastRunErrors ?? this.lastRunErrors,
    );
  }
}
