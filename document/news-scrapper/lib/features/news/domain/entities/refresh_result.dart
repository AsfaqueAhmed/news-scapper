import 'article.dart';

/// Outcome of a scrape run: the refreshed cached articles, any per-source or
/// enrichment errors encountered, and when the run completed.
class RefreshResult {
  final List<Article> articles;
  final List<String> errors;
  final DateTime scrapedAt;

  const RefreshResult({
    required this.articles,
    required this.errors,
    required this.scrapedAt,
  });
}
