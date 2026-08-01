import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_format.dart';
import '../../data/share/share_card_renderer.dart';
import '../../domain/entities/article.dart';
import '../state/news_providers.dart';

/// Lets the user swipe through ready-made share templates and share
/// whichever one is centered.
class SharePreviewScreen extends ConsumerStatefulWidget {
  final Article article;

  const SharePreviewScreen({super.key, required this.article});

  @override
  ConsumerState<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends ConsumerState<SharePreviewScreen> {
  final _pageController = PageController(viewportFraction: 0.82);

  ui.Image? _image;
  bool _loadingImage = true;
  bool _sharing = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) setState(() => _currentPage = page);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final image = await ref.read(newsNotifierProvider.notifier).loadShareImage(widget.article);
    if (!mounted) return;
    setState(() {
      _image = image;
      _loadingImage = false;
    });
  }

  double _currentPageOffset() {
    if (_pageController.hasClients && _pageController.position.haveDimensions) {
      return _pageController.page ?? _currentPage.toDouble();
    }
    return _currentPage.toDouble();
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final template = shareTemplates[_currentPage];
      final config = ShareCardConfig(
        titlePosition: template.titlePosition,
        showTitle: template.showTitle,
      );
      final notifier = ref.read(newsNotifierProvider.notifier);
      final png = await notifier.composeShareCard(widget.article, _image, config);
      await notifier.shareComposedCard(widget.article, png);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not share this article')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = sourceAccent(widget.article.sourceId);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a template')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: _loadingImage
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: shareTemplates.length,
                      itemBuilder: (context, index) => _buildCard(index, accent),
                    ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(shareTemplates.length, (index) {
                final selected = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected ? accent : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Text(
              shareTemplates[_currentPage].label,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: FilledButton.icon(
                onPressed: _loadingImage || _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(_sharing ? 'Sharing…' : 'Share this template'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(int index, Color accent) {
    final template = shareTemplates[index];
    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: AspectRatio(
        aspectRatio: ShareCardRenderer.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox.expand(
            child: CustomPaint(
              painter: _ShareCardPainter(
                image: _image,
                accentColor: accent,
                title: widget.article.title,
                metaText: '${widget.article.sourceName} · ${relativeTime(widget.article.pubDate)}',
                category: widget.article.category,
                config: ShareCardConfig(
                  titlePosition: template.titlePosition,
                  showTitle: template.showTitle,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        final diff = (index - _currentPageOffset()).abs().clamp(0.0, 1.0);
        final scale = 1 - diff * 0.12;
        final opacity = 1 - diff * 0.45;
        return Center(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: card,
    );
  }
}

class _ShareCardPainter extends CustomPainter {
  final ui.Image? image;
  final Color accentColor;
  final String title;
  final String metaText;
  final String? category;
  final ShareCardConfig config;

  _ShareCardPainter({
    required this.image,
    required this.accentColor,
    required this.title,
    required this.metaText,
    required this.category,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    ShareCardRenderer.paint(
      canvas,
      size,
      image: image,
      accentColor: accentColor,
      title: title,
      metaText: metaText,
      category: category,
      config: config,
    );
  }

  @override
  bool shouldRepaint(covariant _ShareCardPainter oldDelegate) => true;
}
