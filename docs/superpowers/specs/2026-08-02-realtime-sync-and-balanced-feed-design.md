# Realtime Auto-Reload + Balanced Per-Source Feed — Design

## Goal

Two related changes to how the app loads and stays current with articles:

1. **Realtime auto-reload**: instead of only refreshing when the user pulls to refresh, the app reloads automatically whenever the backend cron jobs (`fetch-batch`, `backfill-article-images`) successfully change something — driven by Supabase Realtime, not push notifications (no Firebase/FCM involved; this is in-app reactivity while the app is open, not an OS-level push).
2. **Balanced per-source feed loading**: replace the current `ORDER BY pub_date DESC LIMIT 200` query (which lets a handful of high-frequency/broken-date sources dominate — see [2026-08-02: Fix RFC 822 pubDate parsing](../../../lib/features/news/data/datasources/news_remote_data_source.dart)) with fetching exactly the latest 6 articles from each enabled source and merging them. Validated against live data: every one of the ~28 enabled sources now appears, instead of only 6-8.

## Background: why the old query needed to change

`NewsSupabaseDataSource.getArticles()` with no `sourceId` does a single global query capped at 200 rows, ordered by `pub_date desc`, across *all* sources combined. That same flat list backs both the "All" tab and — via client-side filtering in `NewsState.articlesForSource` — every per-source tab too. A source whose articles don't make the global top-200 shows nothing in its own tab, even if it has hundreds of rows in the database. Switching to "latest 6 per source, merged" guarantees every enabled source is represented everywhere the list is used.

## Part 1: Server-side counter (`sync_state`)

New Postgres table, single row:

```sql
create table public.sync_state (
  id smallint primary key default 1,
  version bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint sync_state_singleton check (id = 1)
);

insert into public.sync_state (id, version) values (1, 0);

alter table public.sync_state enable row level security;

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

RLS is read-only for `anon`/`authenticated` — the client needs `SELECT` for Realtime to authorize the subscription, but can never write to the counter directly. Writes only happen via `bump_sync_version()`, called by the edge functions using their service-role client (which bypasses RLS regardless, but the function is the only sanctioned write path). This project's `supabase_realtime` publication is currently empty (Realtime has never been used here) — this migration is what turns it on, scoped to just this one table.

## Part 2: Edge function triggers

- `supabase/functions/fetch-batch/index.ts`: after a run, call `bump_sync_version()` once — but only if the run actually upserted 1 or more articles. A cron tick that found nothing new stays silent.
- `supabase/functions/backfill-article-images/index.ts`: same pattern — call `bump_sync_version()` only if it actually filled in 1 or more images.

No debouncing/coalescing if both happen to fire close together — occasional back-to-back client reloads are cheap and acceptable; simplicity wins here.

## Part 3: Balanced per-source article loading

New method on `NewsSupabaseDataSource`:

```dart
Future<List<ArticleModel>> getLatestPerSource(List<String> sourceIds, {int perSource = 6}) async {
  final results = await Future.wait(
    sourceIds.map((id) => getArticles(sourceId: id, limit: perSource)),
  );
  final merged = results.expand((r) => r).toList()
    ..sort((a, b) => b.pubDate.compareTo(a.pubDate));
  return merged;
}
```

This replaces the flat `getArticles()` call everywhere it currently populates `NewsState.articles`:

- `NewsRepositoryImpl.getCachedNews()` — currently takes no arguments; changes to accept `List<NewsSource> sources` (mirroring `refresh()`, which already takes it), used to build the source-id list for the balanced query.
- `NewsRepositoryImpl.refresh()` — already has `sources` in scope; its final `_supabaseDataSource.getArticles()` call (used to repopulate the returned article list after scraping) switches to the same balanced method.

Ripple effects: `NewsRepository.getCachedNews()` interface signature, `GetCachedArticlesUseCase.call()`, `NewsNotifier.loadFromCache()`, and the dashboard's `_bootstrap()` (which calls `loadFromCache()`) all thread `List<NewsSource> sources` through — sourced from `SettingsState.enabledSources`, already loaded before `loadFromCache()` runs today.

Every tab (All + each per-source tab) is still just this one shared list filtered client-side by `sourceId`, unchanged from today's architecture — so every tab, including per-source tabs, now shows at most 6 articles per source. Confirmed this is the desired behavior, not a regression to fix separately.

## Part 4: Client realtime subscription

New method on `NewsSupabaseDataSource`:

```dart
RealtimeChannel subscribeToSyncUpdates(void Function() onChanged) {
  return _client.channel('sync_state_changes').onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'sync_state',
    callback: (_) => onChanged(),
  ).subscribe();
}
```

New method on `NewsNotifier`: `startListeningForUpdates(List<NewsSource> sources)` — subscribes once (guarded by a `_subscribed` bool so repeated calls are no-ops), and on every `sync_state` change calls the same `loadFromCache(sources)` path used at startup. This **re-reads** from Supabase; it does **not** re-trigger a client-side RSS scrape (`refresh()`) — the server-side cron already did the scraping/backfilling that caused the trigger, so re-scraping on every event would be redundant and wasteful (hits the `fetch-feed` proxy edge function for nothing).

Called once from `DashboardScreen._bootstrap()`, right after the initial `loadFromCache()` and `_syncTabs()` calls, passing `settings.enabledSources`.

## Testing

No new automated tests — matches this project's established pattern (verification via `flutter analyze` / `flutter test`, plus the direct SQL validation already performed against live data for the balanced-query logic during design). The realtime subscription and edge function trigger wiring will be verified manually: trigger a scrape, confirm `sync_state.version` increments, confirm the app reloads without a manual pull-to-refresh.

## Out of scope

- True OS-level push notifications (Firebase Cloud Messaging) — explicitly not what this is. This is in-app auto-reload while the app is open/foregrounded via Supabase Realtime, nothing arrives if the app is closed.
- Per-user notification preferences / filtering by source or category.
- Debouncing or coalescing rapid successive `sync_state` changes.
