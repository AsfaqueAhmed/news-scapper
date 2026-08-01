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
    await newsNotifier.loadFromCache();
    if (!mounted) return;
    setState(() => _syncTabs(ref.read(settingsNotifierProvider)));
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
    await newsNotifier.refresh(
      sources: settings.enabledSources,
      openRouterToken: settings.openRouterToken,
    );
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

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final news = ref.watch(newsNotifierProvider);
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
          final siblings = notifier.groupSiblings(article);
          return ArticleCard(
            article: article,
            siblingSourceCount: siblings.map((a) => a.sourceId).toSet().length,
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
