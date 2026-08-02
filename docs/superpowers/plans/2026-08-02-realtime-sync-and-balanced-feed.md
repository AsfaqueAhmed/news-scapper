# Realtime Auto-Reload + Balanced Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Supabase Realtime-driven auto-reload (the backend cron jobs bump a counter after a successful run; the app reloads automatically) and replace the "All"/per-source article feed's global-top-200 query with a balanced latest-6-per-source query.

**Architecture:** A new single-row `sync_state` table + `bump_sync_version()` SQL function, called by the `fetch-batch` and `backfill-article-images` edge functions after a run that actually changed something. The Flutter app subscribes to that table via `supabase_flutter`'s Realtime Postgres Changes and reloads articles (re-reads from Supabase, does not re-scrape) on every change. Article loading switches from one global-cap query to N parallel per-source queries merged client-side.

**Tech Stack:** Supabase Postgres + Realtime + Edge Functions (Deno/TypeScript), Flutter/Dart with `supabase_flutter` and `flutter_riverpod`.

## Global Constraints

- Supabase project id for all MCP tool calls: `imswemntldphsibfusal`.
- No new automated tests (matches this project's established pattern) — verification is `flutter analyze`, `flutter test`, direct SQL checks, and manual confirmation.
- `bump_sync_version()` is only called when a run actually changed something (upserted ≥1 article / found ≥1 image) — not on every idle cron tick.
- The realtime listener re-reads from Supabase (`loadFromCache`); it must never trigger a client-side RSS re-scrape (`refresh`).

---

### Task 1: Database migration — `sync_state` counter + Realtime

Creates the counter table, its bump function, RLS, and enables it on the Realtime publication (currently empty — this project has never used Realtime before).

**Files:** None in the repo — this is a Supabase Postgres migration applied directly via MCP tool (no local `supabase/migrations` directory exists in this project).

**Interfaces:**
- Produces: table `public.sync_state(id smallint, version bigint, updated_at timestamptz)` (single row, `id=1`); function `public.bump_sync_version() returns bigint` (SQL, `security definer`) — consumed by Task 2's edge functions via `supabase.rpc("bump_sync_version")`, and its underlying table is consumed by Task 3's client code via a Realtime subscription on table `sync_state`.

- [ ] **Step 1: Apply the migration**

Call the `apply_migration` MCP tool with:
- `project_id`: `imswemntldphsibfusal`
- `name`: `add_sync_state_realtime_trigger`
- `query`:

```sql
-- Single-row counter that fetch-batch and backfill-article-images bump
-- after a run that actually changed something. The app subscribes to
-- this table via Realtime and reloads articles whenever it changes,
-- instead of only refreshing on manual pull-to-refresh.
create table public.sync_state (
  id smallint primary key default 1,
  version bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint sync_state_singleton check (id = 1)
);

insert into public.sync_state (id, version) values (1, 0);

alter table public.sync_state enable row level security;

-- Read-only for clients (needed so Realtime can authorize the
-- subscription); writes only happen via bump_sync_version(), called by
-- the edge functions using the service-role key, which bypasses RLS.
create policy "Public read access"
  on public.sync_state
  for select
  to anon, authenticated
  using (true);

create or replace function public.bump_sync_version()
returns bigint
language sql
security definer
set search_path = public
as $$
  update public.sync_state
  set version = version + 1, updated_at = now()
  where id = 1
  returning version;
$$;

alter publication supabase_realtime add table public.sync_state;
```

- [ ] **Step 2: Verify the migration**

Call the `execute_sql` MCP tool with `project_id: imswemntldphsibfusal` and:

```sql
select * from public.sync_state;
```

Expected: one row, `id=1, version=0`.

Then verify the RPC function works and increments it:

```sql
select public.bump_sync_version();
```

Expected: returns `1`. Run `select * from public.sync_state;` again to confirm `version=1`.

Then verify the Realtime publication includes the table:

```sql
select schemaname, tablename from pg_publication_tables where pubname = 'supabase_realtime';
```

Expected: one row, `public.sync_state`.

- [ ] **Step 3: Reset the version back to 0**

The verification step bumped the counter to 1 — reset it so the app's first real trigger is a clean signal, not an artifact of testing. Call `execute_sql` with:

```sql
update public.sync_state set version = 0, updated_at = now() where id = 1;
```

No git commit for this task — it's a database-only change, nothing in the repo changed.

---

### Task 2: Edge functions bump the counter on real changes

`fetch-batch` bumps after a run that upserted ≥1 article (and the upsert itself succeeded); `backfill-article-images` bumps after a run that found ≥1 image.

**Files:**
- Modify: `supabase/functions/fetch-batch/index.ts`
- Modify: `supabase/functions/backfill-article-images/index.ts`

**Interfaces:**
- Consumes: `public.bump_sync_version()` from Task 1, called via `supabase.rpc("bump_sync_version")` (the `supabase-js` client already in scope in both functions as `supabase`).

- [ ] **Step 1: Add the bump call to `fetch-batch`**

In `supabase/functions/fetch-batch/index.ts`, find:

```typescript
  if (deduped.length > 0) {
    // Exclude is_read: a re-scraped article is always freshly parsed as
    // unread, and upserting that would silently clobber a user's "read"
    // state every time this source gets re-fetched. Leaving it out of the
    // payload means new rows still get false (the column default) while
    // existing rows keep whatever is_read they had.
    const rows = deduped.map(({ is_read: _is_read, ...rest }) => rest);
    const { error: upsertError } = await supabase.from("articles").upsert(rows);
    if (upsertError) errors.push(`upsert: ${upsertError.message}`);
  }
```

Replace with:

```typescript
  if (deduped.length > 0) {
    // Exclude is_read: a re-scraped article is always freshly parsed as
    // unread, and upserting that would silently clobber a user's "read"
    // state every time this source gets re-fetched. Leaving it out of the
    // payload means new rows still get false (the column default) while
    // existing rows keep whatever is_read they had.
    const rows = deduped.map(({ is_read: _is_read, ...rest }) => rest);
    const { error: upsertError } = await supabase.from("articles").upsert(rows);
    if (upsertError) {
      errors.push(`upsert: ${upsertError.message}`);
    } else {
      // Bump the app's realtime sync counter -- but only when something
      // actually landed, so idle cron ticks don't trigger client reloads.
      const { error: bumpError } = await supabase.rpc("bump_sync_version");
      if (bumpError) errors.push(`sync bump: ${bumpError.message}`);
    }
  }
```

- [ ] **Step 2: Add the bump call to `backfill-article-images`**

In `supabase/functions/backfill-article-images/index.ts`, find:

```typescript
  if (logRows.length > 0) {
    const { error: logError } = await supabase.from("fetch_log").insert(logRows);
    if (logError) errors.push(`fetch_log insert: ${logError.message}`);
  }

  return new Response(
    JSON.stringify({
      runId,
      candidatesChecked: (candidates ?? []).length,
      imagesFound,
      errors,
      finishedAt: new Date().toISOString(),
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
```

Replace with:

```typescript
  if (logRows.length > 0) {
    const { error: logError } = await supabase.from("fetch_log").insert(logRows);
    if (logError) errors.push(`fetch_log insert: ${logError.message}`);
  }

  if (imagesFound > 0) {
    // Bump the app's realtime sync counter -- but only when something
    // actually landed, so idle cron ticks don't trigger client reloads.
    const { error: bumpError } = await supabase.rpc("bump_sync_version");
    if (bumpError) errors.push(`sync bump: ${bumpError.message}`);
  }

  return new Response(
    JSON.stringify({
      runId,
      candidatesChecked: (candidates ?? []).length,
      imagesFound,
      errors,
      finishedAt: new Date().toISOString(),
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
```

- [ ] **Step 3: Deploy `fetch-batch`**

Read the full current contents of `supabase/functions/fetch-batch/index.ts` (after Step 1's edit) and call the `deploy_edge_function` MCP tool with:
- `project_id`: `imswemntldphsibfusal`
- `name`: `fetch-batch`
- `entrypoint_path`: `index.ts`
- `verify_jwt`: `true` (matches the function's current deployed setting — check via `list_edge_functions` if unsure)
- `files`: `[{ "name": "index.ts", "content": "<the full file content>" }]`

- [ ] **Step 4: Deploy `backfill-article-images`**

Same as Step 3, but with `name: "backfill-article-images"` and the full contents of `supabase/functions/backfill-article-images/index.ts` (after Step 2's edit). `verify_jwt` is also `true` for this function currently.

- [ ] **Step 5: Verify both deployments**

Call `list_edge_functions` with `project_id: imswemntldphsibfusal` and confirm both `fetch-batch` and `backfill-article-images` show a bumped `version` number and a recent `updated_at` compared to before this task.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/fetch-batch/index.ts supabase/functions/backfill-article-images/index.ts
git commit -m "$(cat <<'EOF'
Bump a realtime sync counter after successful cron runs

fetch-batch and backfill-article-images now call the new
bump_sync_version() RPC after a run that actually changed something
(upserted an article / found an image) -- the app will subscribe to
this via Supabase Realtime to auto-reload without manual refresh.
EOF
)"
```

---

### Task 3: Client — balanced feed loading + realtime auto-reload

Replaces the global-cap article query with latest-6-per-source, and wires up a Realtime subscription that reloads the article list on every `sync_state` change.

**Files:**
- Modify: `lib/features/news/data/datasources/news_supabase_data_source.dart`
- Modify: `lib/features/news/domain/repositories/news_repository.dart`
- Modify: `lib/features/news/data/repositories/news_repository_impl.dart`
- Modify: `lib/features/news/domain/usecases/get_cached_articles_usecase.dart`
- Create: `lib/features/news/domain/usecases/subscribe_to_updates_usecase.dart`
- Modify: `lib/features/news/presentation/state/news_providers.dart`
- Modify: `lib/features/news/presentation/state/news_notifier.dart`
- Modify: `lib/features/news/presentation/screens/dashboard_screen.dart`

**Interfaces:**
- Consumes: `NewsSource.id` (existing entity field), `SettingsState.enabledSources` (existing, `List<NewsSource>`).
- Produces: `NewsSupabaseDataSource.getLatestPerSource(List<String> sourceIds, {int perSource = 6}) -> Future<List<ArticleModel>>`; `NewsSupabaseDataSource.subscribeToSyncUpdates(void Function() onChanged) -> void`; `NewsRepository.getCachedNews({required List<NewsSource> sources}) -> Future<CachedNews>` (signature changed from no-args); `NewsRepository.subscribeToUpdates(void Function() onChanged) -> void`; `GetCachedArticlesUseCase.call({required List<NewsSource> sources})` (signature changed); `SubscribeToUpdatesUseCase.call(void Function() onChanged)`; `NewsNotifier.loadFromCache({required List<NewsSource> sources})` (signature changed from no-args); `NewsNotifier.startListeningForUpdates({required List<NewsSource> sources})`.

- [ ] **Step 1: Add the two new data source methods**

Replace the entire contents of `lib/features/news/data/datasources/news_supabase_data_source.dart` with:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/article_model.dart';

/// CRUD for the `articles` table in Supabase Postgres.
class NewsSupabaseDataSource {
  final SupabaseClient _client;
  RealtimeChannel? _syncChannel;

  NewsSupabaseDataSource(this._client);

  /// Excludes `is_read` from the upsert payload: a re-scraped article is
  /// always freshly parsed as unread, and upserting that would silently
  /// clobber a user's "read" state every time the source is re-fetched.
  /// Leaving it out of the payload means new rows still get `false` (the
  /// column default) while existing rows keep whatever `is_read` they had.
  Future<void> upsertArticles(List<ArticleModel> articles) async {
    if (articles.isEmpty) return;
    final rows = articles.map((a) => a.toMap()..remove('is_read')).toList();
    await _client.from('articles').upsert(rows);
  }

  Future<void> updateArticleEnrichment(
    String id, {
    String? groupId,
    String? category,
  }) async {
    final values = <String, Object?>{};
    if (groupId != null) values['group_id'] = groupId;
    if (category != null) values['category'] = category;
    if (values.isEmpty) return;
    await _client.from('articles').update(values).eq('id', id);
  }

  Future<void> markRead(String id) async {
    await _client.from('articles').update({'is_read': true}).eq('id', id);
  }

  Future<List<ArticleModel>> getArticles({String? sourceId, int limit = 200}) async {
    var query = _client.from('articles').select();
    if (sourceId != null) {
      query = query.eq('source_id', sourceId);
    }
    final rows = await query.order('pub_date', ascending: false).limit(limit);
    return rows.map(ArticleModel.fromMap).toList();
  }

  /// Latest [perSource] articles from EACH of [sourceIds], merged and
  /// sorted by publish date. Used instead of a single global-cap query so
  /// every enabled source is represented -- a source with fewer/older
  /// articles no longer gets crowded out of the list by higher-volume or
  /// higher-frequency sources.
  Future<List<ArticleModel>> getLatestPerSource(List<String> sourceIds, {int perSource = 6}) async {
    final results = await Future.wait(
      sourceIds.map((id) => getArticles(sourceId: id, limit: perSource)),
    );
    final merged = results.expand((rows) => rows).toList()
      ..sort((a, b) => b.pubDate.compareTo(a.pubDate));
    return merged;
  }

  Future<List<ArticleModel>> getArticlesByGroup(String groupId) async {
    final rows = await _client
        .from('articles')
        .select()
        .eq('group_id', groupId)
        .order('pub_date', ascending: false);
    return rows.map(ArticleModel.fromMap).toList();
  }

  Future<void> pruneOlderThan(Duration age) async {
    final cutoff = DateTime.now().subtract(age).toIso8601String();
    await _client.from('articles').delete().lt('pub_date', cutoff);
  }

  /// Subscribes to the `sync_state` counter that the fetch-batch and
  /// backfill-article-images edge functions bump after a run that
  /// actually changed something. Calls [onChanged] on every update. Not
  /// idempotent -- callers must guard against subscribing more than once
  /// (see `NewsNotifier.startListeningForUpdates`).
  void subscribeToSyncUpdates(void Function() onChanged) {
    _syncChannel = _client.channel('sync_state_changes').onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'sync_state',
      callback: (_) => onChanged(),
    ).subscribe();
  }
}
```

- [ ] **Step 2: Update the repository interface**

Replace the entire contents of `lib/features/news/domain/repositories/news_repository.dart` with:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../settings/domain/entities/news_source.dart';
import '../../data/share/share_card_renderer.dart';
import '../entities/article.dart';
import '../entities/cached_news.dart';
import '../entities/refresh_result.dart';

abstract class NewsRepository {
  /// Reads current cached articles: the latest few per each of [sources],
  /// not a single global-cap query -- see
  /// `NewsSupabaseDataSource.getLatestPerSource` docs for why.
  Future<CachedNews> getCachedNews({required List<NewsSource> sources});

  /// Scrapes every enabled [sources], stores results, and (if
  /// [openRouterToken] is set) asks the LLM to categorize + group
  /// same-story articles.
  Future<RefreshResult> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  });

  Future<void> markRead(String articleId);

  /// Downloads (and caches) the article's source image for the share
  /// preview editor.
  Future<ui.Image?> loadShareImage(Article article);

  /// Renders the share card -- photo + title overlay per [config] -- as
  /// PNG bytes, without sharing it yet.
  Future<Uint8List> composeShareCard(Article article, ui.Image? image, ShareCardConfig config);

  /// Opens the native share sheet with the already-composed [pngBytes] and
  /// records the share.
  Future<void> shareComposedCard(Article article, Uint8List pngBytes);

  /// Subscribes to backend sync updates; [onChanged] is called whenever
  /// the server-side cron jobs successfully change something, so the
  /// caller can reload without the user pulling to refresh.
  void subscribeToUpdates(void Function() onChanged);
}
```

- [ ] **Step 3: Update the repository implementation**

Replace the entire contents of `lib/features/news/data/repositories/news_repository_impl.dart` with:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:uuid/uuid.dart';

import '../../../settings/domain/entities/news_source.dart';
import '../../domain/entities/article.dart';
import '../../domain/entities/cached_news.dart';
import '../../domain/entities/refresh_result.dart';
import '../../domain/repositories/news_repository.dart';
import '../datasources/news_enrichment_data_source.dart';
import '../datasources/news_supabase_data_source.dart';
import '../datasources/news_prefs_data_source.dart';
import '../datasources/news_remote_data_source.dart';
import '../datasources/share_data_source.dart';
import '../models/article_model.dart';
import '../share/share_card_renderer.dart';

/// AI enrichment (OpenRouter categorization/same-story grouping) is
/// temporarily switched off -- flip to true to re-enable calling the
/// enrich-articles edge function. Nothing else in the pipeline changes.
const _enrichmentEnabled = false;

class NewsRepositoryImpl implements NewsRepository {
  final NewsSupabaseDataSource _supabaseDataSource;
  final NewsRemoteDataSource _remoteDataSource;
  final NewsEnrichmentDataSource _enrichmentDataSource;
  final NewsPrefsDataSource _prefsDataSource;
  final ShareDataSource _shareDataSource;

  NewsRepositoryImpl(
    this._supabaseDataSource,
    this._remoteDataSource,
    this._enrichmentDataSource,
    this._prefsDataSource,
    this._shareDataSource,
  );

  @override
  Future<CachedNews> getCachedNews({required List<NewsSource> sources}) async {
    final articles = await _supabaseDataSource.getLatestPerSource(
      sources.map((s) => s.id).toList(),
    );
    final lastScrapedAt = await _prefsDataSource.getLastScrapedAt();
    final lastShared = await _prefsDataSource.getLastShared();
    return CachedNews(
      articles: articles,
      lastScrapedAt: lastScrapedAt,
      lastShared: lastShared,
    );
  }

  @override
  Future<RefreshResult> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  }) async {
    final errors = <String>[];
    final fetched = <ArticleModel>[];

    for (final source in sources) {
      try {
        fetched.addAll(await _remoteDataSource.fetchSource(source));
      } on RssFetchException catch (e) {
        errors.add('${e.sourceName}: ${e.message}');
      }
    }

    // Some feeds list the same story more than once (e.g. under multiple
    // categories); dedupe by id before a batch upsert, since Postgres
    // rejects an ON CONFLICT DO UPDATE that would touch the same row twice
    // in one statement.
    final dedupedFetched = {for (final a in fetched) a.id: a}.values.toList();

    if (dedupedFetched.isNotEmpty) {
      await _supabaseDataSource.upsertArticles(dedupedFetched);
    }

    // Enrichment runs whenever there's something new to enrich: the edge
    // function uses the user's token if they've set one in Settings,
    // otherwise falls back to the project's own OpenRouter key.
    if (_enrichmentEnabled && dedupedFetched.isNotEmpty) {
      try {
        final enrichments = await _enrichmentDataSource.enrich(
          dedupedFetched,
          runId: const Uuid().v4(),
          apiToken: openRouterToken,
        );
        for (final e in enrichments) {
          await _supabaseDataSource.updateArticleEnrichment(
            e.articleId,
            category: e.category,
            groupId: e.groupId,
          );
        }
      } on OpenRouterException catch (e) {
        errors.add('AI enrichment: ${e.message}');
      }
    }

    await _supabaseDataSource.pruneOlderThan(const Duration(days: 14));

    final articles = await _supabaseDataSource.getLatestPerSource(
      sources.map((s) => s.id).toList(),
    );
    final scrapedAt = DateTime.now();
    await _prefsDataSource.setLastScrapedAt(scrapedAt);

    return RefreshResult(articles: articles, errors: errors, scrapedAt: scrapedAt);
  }

  @override
  Future<void> markRead(String articleId) => _supabaseDataSource.markRead(articleId);

  @override
  Future<ui.Image?> loadShareImage(Article article) =>
      _shareDataSource.loadImage(article.imageUrl);

  @override
  Future<Uint8List> composeShareCard(Article article, ui.Image? image, ShareCardConfig config) =>
      _shareDataSource.composeCard(ArticleModel.fromEntity(article), image, config);

  @override
  Future<void> shareComposedCard(Article article, Uint8List pngBytes) async {
    await _shareDataSource.shareComposedCard(ArticleModel.fromEntity(article), pngBytes);
    await _prefsDataSource.setLastShared(DateTime.now(), article.title);
  }

  @override
  void subscribeToUpdates(void Function() onChanged) =>
      _supabaseDataSource.subscribeToSyncUpdates(onChanged);
}
```

- [ ] **Step 4: Update `GetCachedArticlesUseCase`**

Replace the entire contents of `lib/features/news/domain/usecases/get_cached_articles_usecase.dart` with:

```dart
import '../../../settings/domain/entities/news_source.dart';
import '../entities/cached_news.dart';
import '../repositories/news_repository.dart';

class GetCachedArticlesUseCase {
  final NewsRepository _repository;

  GetCachedArticlesUseCase(this._repository);

  Future<CachedNews> call({required List<NewsSource> sources}) =>
      _repository.getCachedNews(sources: sources);
}
```

- [ ] **Step 5: Create `SubscribeToUpdatesUseCase`**

Create `lib/features/news/domain/usecases/subscribe_to_updates_usecase.dart`:

```dart
import '../repositories/news_repository.dart';

class SubscribeToUpdatesUseCase {
  final NewsRepository _repository;

  SubscribeToUpdatesUseCase(this._repository);

  void call(void Function() onChanged) => _repository.subscribeToUpdates(onChanged);
}
```

- [ ] **Step 6: Wire the new use case into providers**

In `lib/features/news/presentation/state/news_providers.dart`, find:

```dart
import '../../domain/usecases/share_composed_card_usecase.dart';
```

Replace with:

```dart
import '../../domain/usecases/share_composed_card_usecase.dart';
import '../../domain/usecases/subscribe_to_updates_usecase.dart';
```

Then find:

```dart
final groupSiblingsUseCaseProvider =
    Provider<GroupSiblingsUseCase>((ref) => GroupSiblingsUseCase());
```

Replace with:

```dart
final groupSiblingsUseCaseProvider =
    Provider<GroupSiblingsUseCase>((ref) => GroupSiblingsUseCase());

final subscribeToUpdatesUseCaseProvider = Provider<SubscribeToUpdatesUseCase>(
  (ref) => SubscribeToUpdatesUseCase(ref.watch(newsRepositoryProvider)),
);
```

- [ ] **Step 7: Update `NewsNotifier`**

Replace the entire contents of `lib/features/news/presentation/state/news_notifier.dart` with:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/news_source.dart';
import '../../data/share/share_card_renderer.dart';
import '../../domain/entities/article.dart';
import '../../domain/usecases/compose_share_card_usecase.dart';
import '../../domain/usecases/get_cached_articles_usecase.dart';
import '../../domain/usecases/group_siblings_usecase.dart';
import '../../domain/usecases/load_share_image_usecase.dart';
import '../../domain/usecases/mark_article_read_usecase.dart';
import '../../domain/usecases/refresh_articles_usecase.dart';
import '../../domain/usecases/share_composed_card_usecase.dart';
import '../../domain/usecases/subscribe_to_updates_usecase.dart';
import 'news_providers.dart';
import 'news_state.dart';

class NewsNotifier extends Notifier<NewsState> {
  late final GetCachedArticlesUseCase _getCachedArticles;
  late final RefreshArticlesUseCase _refreshArticles;
  late final MarkArticleReadUseCase _markArticleRead;
  late final LoadShareImageUseCase _loadShareImage;
  late final ComposeShareCardUseCase _composeShareCard;
  late final ShareComposedCardUseCase _shareComposedCard;
  late final GroupSiblingsUseCase _groupSiblings;
  late final SubscribeToUpdatesUseCase _subscribeToUpdates;

  bool _listeningForUpdates = false;

  @override
  NewsState build() {
    _getCachedArticles = ref.watch(getCachedArticlesUseCaseProvider);
    _refreshArticles = ref.watch(refreshArticlesUseCaseProvider);
    _markArticleRead = ref.watch(markArticleReadUseCaseProvider);
    _loadShareImage = ref.watch(loadShareImageUseCaseProvider);
    _composeShareCard = ref.watch(composeShareCardUseCaseProvider);
    _shareComposedCard = ref.watch(shareComposedCardUseCaseProvider);
    _groupSiblings = ref.watch(groupSiblingsUseCaseProvider);
    _subscribeToUpdates = ref.watch(subscribeToUpdatesUseCaseProvider);
    return const NewsState();
  }

  List<Article> groupSiblings(Article article) =>
      _groupSiblings(state.articles, article);

  Future<void> loadFromCache({required List<NewsSource> sources}) async {
    final cached = await _getCachedArticles(sources: sources);
    state = state.copyWith(
      articles: cached.articles,
      lastScrapedAt: cached.lastScrapedAt,
      lastShared: cached.lastShared,
    );
  }

  /// Subscribes (once) to backend sync updates so the article list
  /// reloads automatically after a successful server-side scrape/backfill,
  /// without the user needing to pull-to-refresh. Safe to call more than
  /// once -- only the first call actually subscribes.
  void startListeningForUpdates({required List<NewsSource> sources}) {
    if (_listeningForUpdates) return;
    _listeningForUpdates = true;
    _subscribeToUpdates(() => loadFromCache(sources: sources));
  }

  Future<void> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  }) async {
    if (state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, lastRunErrors: []);

    try {
      final result = await _refreshArticles(
        sources: sources,
        openRouterToken: openRouterToken,
      );
      state = state.copyWith(
        articles: result.articles,
        lastScrapedAt: result.scrapedAt,
        lastRunErrors: result.errors,
      );
    } finally {
      state = state.copyWith(isRefreshing: false);
    }
  }

  Future<void> markRead(Article article) async {
    await _markArticleRead(article.id);
    state = state.copyWith(
      articles: [
        for (final a in state.articles)
          if (a.id == article.id) a.copyWith(isRead: true) else a,
      ],
    );
  }

  Future<ui.Image?> loadShareImage(Article article) => _loadShareImage(article);

  Future<Uint8List> composeShareCard(Article article, ui.Image? image, ShareCardConfig config) =>
      _composeShareCard(article, image, config);

  Future<void> shareComposedCard(Article article, Uint8List pngBytes) async {
    await _shareComposedCard(article, pngBytes);
    state = state.copyWith(lastShared: (DateTime.now(), article.title));
  }
}
```

- [ ] **Step 8: Wire it up in the dashboard**

In `lib/features/news/presentation/screens/dashboard_screen.dart`, find:

```dart
  Future<void> _bootstrap() async {
    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    final newsNotifier = ref.read(newsNotifierProvider.notifier);
    if (!ref.read(settingsNotifierProvider).loaded) await settingsNotifier.load();
    await newsNotifier.loadFromCache();
    if (!mounted) return;
    setState(() => _syncTabs(ref.read(settingsNotifierProvider)));
    if (ref.read(newsNotifierProvider).lastScrapedAt == null) {
      _refresh();
    }
  }
```

Replace with:

```dart
  Future<void> _bootstrap() async {
    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    final newsNotifier = ref.read(newsNotifierProvider.notifier);
    if (!ref.read(settingsNotifierProvider).loaded) await settingsNotifier.load();
    final settings = ref.read(settingsNotifierProvider);
    await newsNotifier.loadFromCache(sources: settings.enabledSources);
    newsNotifier.startListeningForUpdates(sources: settings.enabledSources);
    if (!mounted) return;
    setState(() => _syncTabs(settings));
    if (ref.read(newsNotifierProvider).lastScrapedAt == null) {
      _refresh();
    }
  }
```

- [ ] **Step 9: Fix the fake repository in the widget test**

`test/widget_test.dart`'s `_FakeNewsRepository implements NewsRepository` will fail to compile against the new interface. In `test/widget_test.dart`, find:

```dart
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
  Future<ui.Image?> loadShareImage(Article article) async => null;

  @override
  Future<Uint8List> composeShareCard(Article article, ui.Image? image, ShareCardConfig config) async =>
      Uint8List(0);

  @override
  Future<void> shareComposedCard(Article article, Uint8List pngBytes) async {}
}
```

Replace with:

```dart
class _FakeNewsRepository implements NewsRepository {
  @override
  Future<CachedNews> getCachedNews({required List<NewsSource> sources}) async =>
      const CachedNews(articles: []);

  @override
  Future<RefreshResult> refresh({
    required List<NewsSource> sources,
    String? openRouterToken,
  }) async =>
      RefreshResult(articles: const [], errors: const [], scrapedAt: DateTime.now());

  @override
  Future<void> markRead(String articleId) async {}

  @override
  Future<ui.Image?> loadShareImage(Article article) async => null;

  @override
  Future<Uint8List> composeShareCard(Article article, ui.Image? image, ShareCardConfig config) async =>
      Uint8List(0);

  @override
  Future<void> shareComposedCard(Article article, Uint8List pngBytes) async {}

  @override
  void subscribeToUpdates(void Function() onChanged) {}
}
```

- [ ] **Step 10: Verify**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 11: Manual verification against the live backend**

This wiring can't be verified by the automated test suite (it needs a real Realtime connection and real cron runs). Run the app (`flutter run`) and:

1. Confirm the dashboard loads articles from every enabled source (spot-check a source tab that was previously empty, e.g. one of the ~20 sources that never made the old top-200 cutoff — it should now show up to 6 articles).
2. Leave the app open and idle. Watch the Supabase dashboard's Realtime logs (or poll `select version from sync_state;` via SQL) until a cron run bumps the counter.
3. Confirm the app's article list updates on its own within a few seconds of that bump, without you touching pull-to-refresh.

- [ ] **Step 12: Commit**

```bash
git add lib/features/news/data/datasources/news_supabase_data_source.dart lib/features/news/domain/repositories/news_repository.dart lib/features/news/data/repositories/news_repository_impl.dart lib/features/news/domain/usecases/get_cached_articles_usecase.dart lib/features/news/domain/usecases/subscribe_to_updates_usecase.dart lib/features/news/presentation/state/news_providers.dart lib/features/news/presentation/state/news_notifier.dart lib/features/news/presentation/screens/dashboard_screen.dart test/widget_test.dart
git commit -m "$(cat <<'EOF'
Load latest 6 articles per source and auto-reload via Realtime

Replace the global ORDER BY pub_date DESC LIMIT 200 article query
(which let a handful of high-frequency sources crowd out the rest)
with fetching each enabled source's latest 6 articles in parallel and
merging them -- every source is now represented in every tab.

Also subscribe to the new sync_state counter via Supabase Realtime:
the article list now reloads automatically after a successful
server-side scrape/backfill, instead of only on manual
pull-to-refresh.
EOF
)"
```
