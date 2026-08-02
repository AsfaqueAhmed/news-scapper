import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_format.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../settings/presentation/state/settings_providers.dart';
import '../../../settings/presentation/state/settings_state.dart';
import '../../domain/entities/article.dart';
import '../state/news_providers.dart';
import '../widgets/article_card.dart';
import 'news_detail_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  List<String> _tabSourceIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

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

  /// Mutates tab state in place. Safe to call either directly from
  /// `build()` (field changes apply to the in-progress build) or wrapped
  /// in `setState` from an async callback outside build.
  void _syncTabs(SettingsState settings) {
    final ids = ['all', ...settings.enabledSources.map((s) => s.id)];
    if (listEquals(ids, _tabSourceIds)) return;
    _tabSourceIds = ids;
    _tabController?.dispose();
    _tabController = TabController(length: ids.length, vsync: this);
  }

  Future<void> _refresh() async {
    final settings = ref.read(settingsNotifierProvider);
    final newsNotifier = ref.read(newsNotifierProvider.notifier);
    try {
      await newsNotifier.refresh(
        sources: settings.enabledSources,
        openRouterToken: settings.openRouterToken,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: $e')),
        );
      }
      return;
    }
    final errors = ref.read(newsNotifierProvider).lastRunErrors;
    if (mounted && errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Some sources failed: ${errors.join('; ')}')),
      );
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    _syncTabs(settings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('News'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Column(
            children: [
              const _StatusBar(),
              if (_tabController != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: _tabSourceIds.map((id) {
                      if (id == 'all') return const Tab(text: 'All');
                      final source = settings.sources.firstWhere((s) => s.id == id);
                      return Tab(text: source.name);
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: _tabController == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: _tabSourceIds.map((id) {
                final sourceId = id == 'all' ? null : id;
                return _NewsList(sourceId: sourceId, onRefresh: _refresh);
              }).toList(),
            ),
    );
  }
}

bool listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final news = ref.watch(newsNotifierProvider);
    final theme = Theme.of(context);
    final lastShared = news.lastShared;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text('Updated ${relativeTime(news.lastScrapedAt)}', style: theme.textTheme.labelSmall),
          if (news.isRefreshing) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          if (lastShared != null) ...[
            Text('  ·  ', style: theme.textTheme.labelSmall),
            Icon(Icons.ios_share_rounded, size: 12, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Shared ${relativeTime(lastShared.$1)}',
                style: theme.textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewsList extends ConsumerWidget {
  final String? sourceId;
  final Future<void> Function() onRefresh;

  const _NewsList({required this.sourceId, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final news = ref.watch(newsNotifierProvider);
    final notifier = ref.read(newsNotifierProvider.notifier);
    final articles = news.articlesForSource(sourceId);

    if (articles.isEmpty && !news.isRefreshing) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: _EmptyState(onRefresh: onRefresh),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: articles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final article = articles[index];
          final siblings = notifier.groupSiblings(article);
          final siblingCount = siblings.map((a) => a.sourceId).toSet().length;
          if (index == 0) {
            return FeaturedArticleCard(
              article: article,
              siblingSourceCount: siblingCount,
              onTap: () => _openDetail(context, ref, article),
            );
          }
          return ArticleCard(
            article: article,
            siblingSourceCount: siblingCount,
            onTap: () => _openDetail(context, ref, article),
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref, Article article) {
    ref.read(newsNotifierProvider.notifier).markRead(article);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewsDetailScreen(article: article)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.rss_feed_rounded,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text('No articles yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Pull down or tap refresh to scrape the latest stories.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh now'),
            ),
          ],
        ),
      ),
    );
  }
}
