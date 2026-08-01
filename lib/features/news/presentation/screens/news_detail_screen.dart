import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final siblings =
        notifier.groupSiblings(article).where((a) => a.id != article.id).toList();

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open original article',
            onPressed: () => _openLink(context, article.link),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () => ref.read(newsNotifierProvider.notifier).shareArticle(article),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (article.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: article.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 16),
          Text(article.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(article.sourceName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
              Text('· ${relativeTime(article.pubDate)}'),
              if (article.category != null) Chip(label: Text(article.category!)),
            ],
          ),
          const SizedBox(height: 16),
          if (article.description != null)
            Text(article.description!, style: Theme.of(context).textTheme.bodyLarge),
          if (siblings.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Also covered by', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...siblings.map(
              (sibling) => Card(
                child: ListTile(
                  title: Text(sibling.sourceName),
                  subtitle: Text(sibling.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openLink(context, sibling.link),
                ),
              ),
            ),
          ],
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
