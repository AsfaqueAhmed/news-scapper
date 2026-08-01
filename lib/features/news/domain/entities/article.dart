class Article {
  final String id;
  final String title;
  final String link;
  final String? description;
  final String? imageUrl;
  final DateTime pubDate;
  final String sourceId;
  final String sourceName;

  /// Shared identifier assigned when the LLM detects this article covers
  /// the same story as other articles from different sources.
  final String? groupId;

  /// LLM-assigned topic category, e.g. "Politics", "Technology".
  final String? category;

  final bool isRead;

  const Article({
    required this.id,
    required this.title,
    required this.link,
    required this.pubDate,
    required this.sourceId,
    required this.sourceName,
    this.description,
    this.imageUrl,
    this.groupId,
    this.category,
    this.isRead = false,
  });

  Article copyWith({
    String? groupId,
    String? category,
    bool? isRead,
  }) {
    return Article(
      id: id,
      title: title,
      link: link,
      description: description,
      imageUrl: imageUrl,
      pubDate: pubDate,
      sourceId: sourceId,
      sourceName: sourceName,
      groupId: groupId ?? this.groupId,
      category: category ?? this.category,
      isRead: isRead ?? this.isRead,
    );
  }
}
