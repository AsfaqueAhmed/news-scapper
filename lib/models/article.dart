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

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'link': link,
      'description': description,
      'imageUrl': imageUrl,
      'pubDate': pubDate.toIso8601String(),
      'sourceId': sourceId,
      'sourceName': sourceName,
      'groupId': groupId,
      'category': category,
      'isRead': isRead ? 1 : 0,
    };
  }

  factory Article.fromMap(Map<String, Object?> map) {
    return Article(
      id: map['id'] as String,
      title: map['title'] as String,
      link: map['link'] as String,
      description: map['description'] as String?,
      imageUrl: map['imageUrl'] as String?,
      pubDate: DateTime.parse(map['pubDate'] as String),
      sourceId: map['sourceId'] as String,
      sourceName: map['sourceName'] as String,
      groupId: map['groupId'] as String?,
      category: map['category'] as String?,
      isRead: (map['isRead'] as int) == 1,
    );
  }
}
