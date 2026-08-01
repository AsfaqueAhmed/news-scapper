import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../providers/news_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/date_format.dart';
import '../widgets/article_card.dart';
import 'news_detail_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<String> _tabSourceIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final settings = context.read<SettingsProvider>();
    final news = context.read<NewsProvider>();
    if (!settings.loaded) await settings.load();
    await news.loadFromCache();
    if (!mounted) return;
    setState(() => _syncTabs(settings));
    if (news.lastScrapedAt == null) {
      _refresh();
    }
  }

  /// Mutates tab state in place. Safe to call either directly from
  /// `build()` (field changes apply to the in-progress build) or wrapped
  /// in `setState` from an async callback outside build.
  void _syncTabs(SettingsProvider settings) {
    final ids = ['all', ...settings.enabledSources.map((s) => s.id)];
    if (listEquals(ids, _tabSourceIds)) return;
    _tabSourceIds = ids;
    _tabController?.dispose();
    _tabController = TabController(length: ids.length, vsync: this);
  }

  Future<void> _refresh() async {
    final settings = context.read<SettingsProvider>();
    final news = context.read<NewsProvider>();
    await news.refresh(
      sources: settings.enabledSources,
      openRouterToken: settings.openRouterToken,
    );
    if (mounted && news.lastRunErrors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Some sources failed: ${news.lastRunErrors.join('; ')}')),
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
    final settings = context.watch<SettingsProvider>();
    _syncTabs(settings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('News Dashboard'),
        bottom: _tabController == null
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _tabSourceIds.map((id) {
                  if (id == 'all') return const Tab(text: 'All');
                  final source = settings.sources.firstWhere((s) => s.id == id);
                  return Tab(text: source.name);
                }).toList(),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const _StatusBar(),
          Expanded(
            child: _tabController == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: _tabSourceIds.map((id) {
                      final sourceId = id == 'all' ? null : id;
                      return _NewsList(sourceId: sourceId, onRefresh: _refresh);
                    }).toList(),
                  ),
          ),
        ],
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

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final news = context.watch<NewsProvider>();
    final theme = Theme.of(context);
    final lastShared = news.lastShared;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.update, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Last scraped: ${relativeTime(news.lastScrapedAt)}',
                style: theme.textTheme.bodySmall,
              ),
              if (news.isRefreshing) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.share, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lastShared == null
                      ? 'Last shared: Never'
                      : 'Last shared: ${lastShared.$2} (${relativeTime(lastShared.$1)})',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewsList extends StatelessWidget {
  final String? sourceId;
  final Future<void> Function() onRefresh;

  const _NewsList({required this.sourceId, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final news = context.watch<NewsProvider>();
    final articles = news.articlesForSource(sourceId);

    if (articles.isEmpty && !news.isRefreshing) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No articles yet. Pull to refresh.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: articles.length,
        itemBuilder: (context, index) {
          final article = articles[index];
          final siblings = news.groupSiblings(article);
          return ArticleCard(
            article: article,
            siblingSourceCount: siblings.map((a) => a.sourceId).toSet().length,
            onTap: () => _openDetail(context, article),
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, Article article) {
    context.read<NewsProvider>().markRead(article);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewsDetailScreen(article: article)),
    );
  }
}
