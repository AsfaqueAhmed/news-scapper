import '../../domain/entities/news_source.dart';

class NewsSourceModel extends NewsSource {
  const NewsSourceModel({
    required super.id,
    required super.name,
    required super.feedUrl,
    super.enabled = true,
  });

  factory NewsSourceModel.fromEntity(NewsSource source) => NewsSourceModel(
        id: source.id,
        name: source.name,
        feedUrl: source.feedUrl,
        enabled: source.enabled,
      );

  /// Maps to the `public.sources` table's (snake_case) columns.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'feed_url': feedUrl,
      'enabled': enabled,
    };
  }

  factory NewsSourceModel.fromMap(Map<String, Object?> map) {
    return NewsSourceModel(
      id: map['id'] as String,
      name: map['name'] as String,
      feedUrl: map['feed_url'] as String,
      enabled: map['enabled'] as bool,
    );
  }
}
