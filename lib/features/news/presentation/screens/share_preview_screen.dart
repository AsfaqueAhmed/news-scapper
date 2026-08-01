import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_format.dart';
import '../../data/share/share_card_renderer.dart';
import '../../domain/entities/article.dart';
import '../state/news_providers.dart';

/// Lets the user pick a title layout, toggle the title on/off, and
/// zoom/pan the photo before the native share sheet opens.
class SharePreviewScreen extends ConsumerStatefulWidget {
  final Article article;

  const SharePreviewScreen({super.key, required this.article});

  @override
  ConsumerState<SharePreviewScreen> createState() => _SharePreviewScreenState();
}

class _SharePreviewScreenState extends ConsumerState<SharePreviewScreen> {
  ui.Image? _image;
  bool _loadingImage = true;
  bool _sharing = false;
  ShareCardConfig _config = const ShareCardConfig();
  double _startZoom = 1;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final image = await ref.read(newsNotifierProvider.notifier).loadShareImage(widget.article);
    if (!mounted) return;
    setState(() {
      _image = image;
      _loadingImage = false;
    });
  }

  void _selectTemplate(ShareTemplate template) {
    setState(() {
      _config = _config.copyWith(
        titlePosition: template.titlePosition,
        showTitle: template.showTitle,
      );
    });
  }

  void _resetFraming() {
    setState(() => _config = _config.copyWith(zoom: ShareCardConfig.minZoom, pan: Offset.zero));
  }

  void _onScaleStart(ScaleStartDetails details) => _startZoom = _config.zoom;

  void _onScaleUpdate(ScaleUpdateDetails details, Size cardSize) {
    if (_image == null) return;
    final newZoom =
        (_startZoom * details.scale).clamp(ShareCardConfig.minZoom, ShareCardConfig.maxZoom);
    final dx = details.focalPointDelta.dx / cardSize.width;
    final dy = details.focalPointDelta.dy / cardSize.height;
    setState(() {
      _config = _config.copyWith(
        zoom: newZoom,
        pan: Offset(
          (_config.pan.dx - dx * 2).clamp(-1.0, 1.0),
          (_config.pan.dy - dy * 2).clamp(-1.0, 1.0),
        ),
      );
    });
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final notifier = ref.read(newsNotifierProvider.notifier);
      final png = await notifier.composeShareCard(widget.article, _image, _config);
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
    final isFramable = _image != null;
    final canReset = _config.zoom != ShareCardConfig.minZoom || _config.pan != Offset.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('Share preview')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: AspectRatio(
                    aspectRatio: ShareCardRenderer.aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _loadingImage
                          ? ColoredBox(
                              color: accent.withValues(alpha: 0.15),
                              child: const Center(child: CircularProgressIndicator()),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final cardSize = constraints.biggest;
                                return GestureDetector(
                                  onScaleStart: isFramable ? _onScaleStart : null,
                                  onScaleUpdate:
                                      isFramable ? (d) => _onScaleUpdate(d, cardSize) : null,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _ShareCardPainter(
                                            image: _image,
                                            accentColor: accent,
                                            title: widget.article.title,
                                            metaText:
                                                '${widget.article.sourceName} · ${relativeTime(widget.article.pubDate)}',
                                            category: widget.article.category,
                                            config: _config,
                                          ),
                                        ),
                                      ),
                                      if (canReset)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: _ResetButton(onTap: _resetFraming),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
            if (_image != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Drag to reposition · pinch to zoom',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Show title', style: theme.textTheme.titleSmall),
                  Switch(
                    value: _config.showTitle,
                    onChanged: (value) => setState(() => _config = _config.copyWith(showTitle: value)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 88,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: shareTemplates.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final template = shareTemplates[index];
                  final selected = template.titlePosition == _config.titlePosition &&
                      template.showTitle == _config.showTitle;
                  return _TemplateChip(
                    template: template,
                    selected: selected,
                    accent: accent,
                    onTap: () => _selectTemplate(template),
                  );
                },
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
                label: Text(_sharing ? 'Sharing…' : 'Share'),
              ),
            ),
          ],
        ),
      ),
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

class _ResetButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ResetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  final ShareTemplate template;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _TemplateChip({
    required this.template,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  IconData get _icon => switch (template.id) {
        'news_card' => Icons.newspaper_rounded,
        'bottom' => Icons.vertical_align_bottom_rounded,
        'top' => Icons.vertical_align_top_rounded,
        'left' => Icons.format_align_left_rounded,
        'right' => Icons.format_align_right_rounded,
        'center' => Icons.format_align_center_rounded,
        _ => Icons.image_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_icon, size: 22, color: selected ? accent : theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              template.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected ? accent : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
