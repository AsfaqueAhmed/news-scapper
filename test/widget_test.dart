import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:news_scrapper/app.dart';
import 'package:news_scrapper/features/news/domain/entities/article.dart';
import 'package:news_scrapper/features/news/domain/entities/cached_news.dart';
import 'package:news_scrapper/features/news/domain/entities/refresh_result.dart';
import 'package:news_scrapper/features/news/domain/repositories/news_repository.dart';
import 'package:news_scrapper/features/news/presentation/state/news_providers.dart';
import 'package:news_scrapper/features/settings/domain/entities/news_source.dart';
import 'package:news_scrapper/features/settings/domain/repositories/settings_repository.dart';
import 'package:news_scrapper/features/settings/presentation/state/settings_providers.dart';

/// Fakes stand in for the Supabase-backed repositories so this smoke test
/// doesn't depend on live network access (blocked by default under
/// TestWidgetsFlutterBinding anyway).
class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<List<NewsSource>> getSources() async => [];

  @override
  Future<void> upsertSource(NewsSource source) async {}

  @override
  Future<void> deleteSource(String id) async {}

  @override
  Future<String?> getOpenRouterToken() async => null;

  @override
  Future<void> setOpenRouterToken(String? token) async {}
}

class _FakeNewsRepository implements NewsRepository {
  @override
  Future<CachedNews> getCachedNews() async => const CachedNews(articles: []);

  @override
  Future<RefreshResult> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  }) async =>
      RefreshResult(articles: const [], errors: const [], scrapedAt: DateTime.now());

  @override
  Future<void> markRead(String articleId) async {}

  @override
  Future<void> shareArticle(Article article) async {}
}

void main() {
  testWidgets('Dashboard renders with app bar', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
          newsRepositoryProvider.overrideWithValue(_FakeNewsRepository()),
        ],
        child: const NewsScrapperApp(),
      ),
    );
    await tester.pump();

    expect(find.text('News Dashboard'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
