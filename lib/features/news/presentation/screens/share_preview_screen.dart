import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_format.dart';
import '../../data/share/share_card_renderer.dart';
import '../../domain/entities/article.dart';
import '../state/news_providers.dart';

enum _ViewMode { carousel, grid }

/// Lets the user browse ready-made share templates -- as a swipeable
/// carousel or a scannable grid -- and share whichever one is selected.
class SharePreviewScreen extends ConsumerStatefulWidget {
  final Article article;

  const SharePreviewScreen({super.key, required this.article});

  @override
  ConsumerState<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends ConsumerState<SharePreviewScreen> {
  late PageController _pageController;

  ui.Image? _image;
  ui.Image? _logo;
  bool _loadingImage = true;
  bool _sharing = false;
  int _currentPage = 0;
  _ViewMode _viewMode = _ViewMode.carousel;
  bool _showBadge = true;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _pageController = _newPageController(_currentPage);
  }

  PageController _newPageController(int initialPage) {
    final controller = PageController(viewportFraction: 0.82, initialPage: initialPage);
    controller.addListener(() {
      final page = controller.page?.round() ?? 0;
      if (page != _currentPage) setState(() => _currentPage = page);
    });
    return controller;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    final imageFuture = ref.read(newsNotifierProvider.notifier).loadShareImage(widget.article);
    final logoFuture = ShareCardRenderer.loadBrandLogo();
    final image = await imageFuture;
    final logo = await logoFuture;
    if (!mounted) return;
    setState(() {
      _image = image;
      _logo = logo;
      _loadingImage = false;
    });
  }

  double _currentPageOffset() {
    if (_pageController.hasClients && _pageController.position.haveDimensions) {
      return _pageController.page ?? _currentPage.toDouble();
    }
    return _currentPage.toDouble();
  }

  void _toggleViewMode() {
    setState(() {
      if (_viewMode == _ViewMode.carousel) {
        _viewMode = _ViewMode.grid;
      } else {
        _viewMode = _ViewMode.carousel;
        _pageController.dispose();
        _pageController = _newPageController(_currentPage);
      }
    });
  }

  void _selectTemplate(int index) {
    setState(() => _currentPage = index);
  }

  ShareCardConfig _configFor(ShareTemplate template) {
    return ShareCardConfig(
      titlePosition: template.titlePosition,
      showTitle: template.showTitle,
      showBadge: _showBadge,
    );
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final template = shareTemplates[_currentPage];
      final config = _configFor(template);
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
    final isGrid = _viewMode == _ViewMode.grid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a template'),
        actions: [
          IconButton(
            icon: Icon(isGrid ? Icons.view_carousel_rounded : Icons.grid_view_rounded),
            tooltip: isGrid ? 'Switch to carousel view' : 'Switch to grid view',
            onPressed: _loadingImage ? null : _toggleViewMode,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: _loadingImage
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : isGrid
                      ? _buildGrid(accent)
                      : _buildCarousel(accent),
            ),
            const SizedBox(height: 18),
            if (!isGrid)
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
            if (const {TitlePosition.ribbon, TitlePosition.card}
                .contains(shareTemplates[_currentPage].titlePosition))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Show "Breaking News" banner',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Switch(
                      value: _showBadge,
                      activeThumbColor: accent,
                      onChanged: (value) => setState(() => _showBadge = value),
                    ),
                  ],
                ),
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

  Widget _buildCarousel(Color accent) {
    return PageView.builder(
      controller: _pageController,
      itemCount: shareTemplates.length,
      itemBuilder: (context, index) => _buildCarouselCard(index, accent),
    );
  }

  Widget _buildCarouselCard(int index, Color accent) {
    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: _templateCard(index, accent),
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

  Widget _buildGrid(Color accent) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: shareTemplates.length,
      itemBuilder: (context, index) {
        final selected = index == _currentPage;
        return GestureDetector(
          onTap: () => _selectTemplate(index),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? accent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: _templateCard(index, accent),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                shareTemplates[index].label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? accent : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _templateCard(int index, Color accent) {
    final template = shareTemplates[index];
    return AspectRatio(
      aspectRatio: ShareCardRenderer.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _ShareCardPainter(
              image: _image,
              logo: _logo,
              accentColor: accent,
              title: widget.article.title,
              description: widget.article.description,
              metaText: '${widget.article.sourceName} · ${relativeTime(widget.article.pubDate)}',
              category: widget.article.category,
              config: _configFor(template),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareCardPainter extends CustomPainter {
  final ui.Image? image;
  final ui.Image? logo;
  final Color accentColor;
  final String title;
  final String? description;
  final String metaText;
  final String? category;
  final ShareCardConfig config;

  _ShareCardPainter({
    required this.image,
    required this.logo,
    required this.accentColor,
    required this.title,
    required this.description,
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
      logo: logo,
      accentColor: accentColor,
      title: title,
      description: description,
      metaText: metaText,
      category: category,
      config: config,
    );
  }

  @override
  bool shouldRepaint(covariant _ShareCardPainter oldDelegate) => true;
}
