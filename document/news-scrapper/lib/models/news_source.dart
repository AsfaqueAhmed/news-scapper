class NewsSource {
  final String id;
  final String name;
  final String feedUrl;
  final bool enabled;

  const NewsSource({
    required this.id,
    required this.name,
    required this.feedUrl,
    this.enabled = true,
  });

  NewsSource copyWith({String? name, String? feedUrl, bool? enabled}) {
    return NewsSource(
      id: id,
      name: name ?? this.name,
      feedUrl: feedUrl ?? this.feedUrl,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'feedUrl': feedUrl,
      'enabled': enabled ? 1 : 0,
    };
  }

  factory NewsSource.fromMap(Map<String, Object?> map) {
    return NewsSource(
      id: map['id'] as String,
      name: map['name'] as String,
      feedUrl: map['feedUrl'] as String,
      enabled: (map['enabled'] as int) == 1,
    );
  }

  static const List<NewsSource> defaults = [
    NewsSource(
      id: 'bbc-news',
      name: 'BBC News',
      feedUrl: 'http://feeds.bbci.co.uk/news/rss.xml',
    ),
    NewsSource(
      id: 'al-jazeera',
      name: 'Al Jazeera',
      feedUrl: 'https://www.aljazeera.com/xml/rss/all.xml',
    ),
    NewsSource(
      id: 'npr-news',
      name: 'NPR News',
      feedUrl: 'https://feeds.npr.org/1001/rss.xml',
    ),
    NewsSource(
      id: 'the-guardian',
      name: 'The Guardian',
      feedUrl: 'https://www.theguardian.com/world/rss',
    ),
    NewsSource(
      id: 'techcrunch',
      name: 'TechCrunch',
      feedUrl: 'https://techcrunch.com/feed/',
    ),
  ];
}
