import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_format.dart';
import '../../domain/entities/article.dart';
import '../state/news_providers.dart';

class NewsDetailScreen extends ConsumerWidget {
  final Article article;

  const NewsDetailScreen({super.key, required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(newsNotifierProvider); // rebuild when articles change
    final notifier = ref.read(newsNotifierProvider.notifier);
    final theme = Theme.of(context);
    final accent = sourceAccent(article.sourceId);
    final siblings =
        notifier.groupSiblings(article).where((a) => a.id != article.id).toList();
    final hasImage = article.imageUrl != null;

    return Scaffold(
      extendBodyBehindAppBar: hasImage,
      appBar: AppBar(
        backgroundColor: hasImage ? Colors.transparent : null,
        foregroundColor: hasImage ? Colors.white : null,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: 'Open original article',
            onPressed: () => _openLink(context, article.link),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share',
            onPressed: () => ref.read(newsNotifierProvider.notifier).shareArticle(article),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (hasImage)
            AspectRatio(
              aspectRatio: 16 / 11,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: article.imageUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => ColoredBox(color: accent.withValues(alpha: 0.25)),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        stops: const [0, 0.4, 1],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        article.title,
                        style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasImage) ...[
                  Text(article.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      article.sourceName,
                      style: theme.textTheme.titleSmall?.copyWith(color: accent),
                    ),
                    const SizedBox(width: 6),
                    Text('· ${relativeTime(article.pubDate)}', style: theme.textTheme.bodySmall),
                  ],
                ),
                if (article.category != null) ...[
                  const SizedBox(height: 10),
                  Chip(label: Text(article.category!)),
                ],
                if (article.description != null) ...[
                  const SizedBox(height: 18),
                  Text(article.description!, style: theme.textTheme.bodyLarge),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => _openLink(context, article.link),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Read full article'),
                ),
                if (siblings.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Also covered by', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  ...siblings.map((sibling) => _SiblingTile(
                        article: sibling,
                        onTap: () => _openLink(context, sibling.link),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    }
  }
}

class _SiblingTile extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;

  const _SiblingTile({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = sourceAccent(article.sourceId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.sourceName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
