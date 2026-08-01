import '../../domain/entities/article.dart';

class ArticleModel extends Article {
  const ArticleModel({
    required super.id,
    required super.title,
    required super.link,
    required super.pubDate,
    required super.sourceId,
    required super.sourceName,
    super.description,
    super.imageUrl,
    super.groupId,
    super.category,
    super.isRead = false,
  });

  factory ArticleModel.fromEntity(Article article) => ArticleModel(
        id: article.id,
        title: article.title,
        link: article.link,
        pubDate: article.pubDate,
        sourceId: article.sourceId,
        sourceName: article.sourceName,
        description: article.description,
        imageUrl: article.imageUrl,
        groupId: article.groupId,
        category: article.category,
        isRead: article.isRead,
      );

  /// Maps to the `public.articles` table's (snake_case) columns.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'link': link,
      'description': description,
      'image_url': imageUrl,
      'pub_date': pubDate.toIso8601String(),
      'source_id': sourceId,
      'source_name': sourceName,
      'group_id': groupId,
      'category': category,
      'is_read': isRead,
    };
  }

  factory ArticleModel.fromMap(Map<String, Object?> map) {
    return ArticleModel(
      id: map['id'] as String,
      title: map['title'] as String,
      link: map['link'] as String,
      description: map['description'] as String?,
      imageUrl: map['image_url'] as String?,
      pubDate: DateTime.parse(map['pub_date'] as String),
      sourceId: map['source_id'] as String,
      sourceName: map['source_name'] as String,
      groupId: map['group_id'] as String?,
      category: map['category'] as String?,
      isRead: map['is_read'] as bool,
    );
  }
}
