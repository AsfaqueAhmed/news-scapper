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
}
