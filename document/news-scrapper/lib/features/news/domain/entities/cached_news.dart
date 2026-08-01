import 'article.dart';

/// The locally cached news state used to populate the dashboard on launch.
class CachedNews {
  final List<Article> articles;
  final DateTime? lastScrapedAt;
  final (DateTime, String)? lastShared;

  const CachedNews({
    required this.articles,
    this.lastScrapedAt,
    this.lastShared,
  });
}
