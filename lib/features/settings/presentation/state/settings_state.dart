import '../../domain/entities/news_source.dart';

class SettingsState {
  final List<NewsSource> sources;
  final String? openRouterToken;
  final bool loaded;

  const SettingsState({
    this.sources = const [],
    this.openRouterToken,
    this.loaded = false,
  });

  List<NewsSource> get enabledSources =>
      sources.where((s) => s.enabled).toList();

  bool get hasOpenRouterToken =>
      openRouterToken != null && openRouterToken!.isNotEmpty;

  SettingsState copyWith({
    List<NewsSource>? sources,
    String? openRouterToken,
    bool clearToken = false,
    bool? loaded,
  }) {
    return SettingsState(
      sources: sources ?? this.sources,
      openRouterToken:
          clearToken ? null : (openRouterToken ?? this.openRouterToken),
      loaded: loaded ?? this.loaded,
    );
  }
}
