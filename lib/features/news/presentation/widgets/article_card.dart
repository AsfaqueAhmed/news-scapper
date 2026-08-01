import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_format.dart';
import '../../domain/entities/article.dart';

class ArticleCard extends StatelessWidget {
  final Article article;
  final int siblingSourceCount;
  final VoidCallback onTap;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    this.siblingSourceCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = sourceAccent(article.sourceId);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (article.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: article.imageUrl!,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => SizedBox(
                      width: 96,
                      height: 96,
                      child: ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SourceRow(
                      accent: accent,
                      sourceName: article.sourceName,
                      pubDate: article.pubDate,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: article.isRead ? FontWeight.w500 : FontWeight.w800,
                        color: article.isRead
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                        height: 1.25,
                      ),
                    ),
                    if (article.category != null || siblingSourceCount > 1) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (article.category != null) _Tag(label: article.category!),
                          if (siblingSourceCount > 1)
                            _Tag(
                              icon: Icons.dynamic_feed_rounded,
                              label: '$siblingSourceCount sources',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-bleed hero treatment for the top story in a list: image fills the
/// card with the headline overlaid on a gradient scrim, matching the
/// "lead story" convention of most news apps.
class FeaturedArticleCard extends StatelessWidget {
  final Article article;
  final int siblingSourceCount;
  final VoidCallback onTap;

  const FeaturedArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    this.siblingSourceCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = sourceAccent(article.sourceId);
    final hasImage = article.imageUrl != null;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                CachedNetworkImage(
                  imageUrl: article.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => ColoredBox(color: accent.withValues(alpha: 0.25)),
                )
              else
                ColoredBox(color: accent.withValues(alpha: 0.25)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: hasImage ? 0.75 : 0.55),
                    ],
                    stops: const [0.35, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Tag(label: 'Top story', color: accent, dark: true),
                        if (article.category != null)
                          _Tag(label: article.category!, dark: true),
                        if (siblingSourceCount > 1)
                          _Tag(
                            icon: Icons.dynamic_feed_rounded,
                            label: '$siblingSourceCount sources',
                            dark: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${article.sourceName} · ${relativeTime(article.pubDate)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final Color accent;
  final String sourceName;
  final DateTime pubDate;

  const _SourceRow({required this.accent, required this.sourceName, required this.pubDate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            sourceName,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(' · ${relativeTime(pubDate)}', style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final bool dark;

  const _Tag({required this.label, this.icon, this.color, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = dark ? Colors.white : theme.colorScheme.onSurfaceVariant;
    final bg = dark
        ? (color ?? Colors.white).withValues(alpha: color != null ? 0.9 : 0.18)
        : theme.colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
