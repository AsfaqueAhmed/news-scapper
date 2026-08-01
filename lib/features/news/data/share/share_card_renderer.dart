import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Which designed layout the card uses. Ignored when
/// [ShareCardConfig.showTitle] is false (photo only, no overlay at all).
enum TitlePosition { ribbon, card, panel, spotlight, minimal }

/// User-adjustable state for the share card editor: which template layout
/// is active (or whether it's shown at all) and how the photo is framed.
class ShareCardConfig {
  final TitlePosition titlePosition;
  final bool showTitle;

  /// Fixed brand color for this template's banner/panel/pill (e.g. the
  /// "Breaking Red" vs "Breaking Navy" variants). Null falls back to the
  /// article source's own accent color.
  final Color? paletteColor;

  /// 1.0 = default cover crop, larger zooms in on the photo.
  final double zoom;

  /// Pan of the photo within the crop, each axis in [-1, 1] (0 = centered).
  final Offset pan;

  const ShareCardConfig({
    this.titlePosition = TitlePosition.ribbon,
    this.showTitle = true,
    this.paletteColor,
    this.zoom = 1.0,
    this.pan = Offset.zero,
  });

  static const double minZoom = 1.0;
  static const double maxZoom = 3.0;

  ShareCardConfig copyWith({
    TitlePosition? titlePosition,
    bool? showTitle,
    Color? paletteColor,
    double? zoom,
    Offset? pan,
  }) {
    return ShareCardConfig(
      titlePosition: titlePosition ?? this.titlePosition,
      showTitle: showTitle ?? this.showTitle,
      paletteColor: paletteColor ?? this.paletteColor,
      zoom: zoom ?? this.zoom,
      pan: pan ?? this.pan,
    );
  }
}

class ShareTemplate {
  final String id;
  final String label;
  final TitlePosition titlePosition;
  final bool showTitle;
  final Color? paletteColor;

  const ShareTemplate({
    required this.id,
    required this.label,
    required this.titlePosition,
    this.showTitle = true,
    this.paletteColor,
  });
}

const _white = Color(0xFFFFFFFF);
const _nearBlack = Color(0xFF15151A);
const _breakingRed = Color(0xFFE0272B);
const _breakingBlack = Color(0xFF1A1A1E);
const _navy = Color(0xFF1B3358);
const _mustard = Color(0xFFE8A733);
const _forest = Color(0xFF1F5C4A);
const _maroon = Color(0xFF5C1A2B);
const _amber = Color(0xFFF2994A);
const _plum = Color(0xFF4A2545);

const List<ShareTemplate> shareTemplates = [
  ShareTemplate(id: 'ribbon_red', label: 'Breaking Red', titlePosition: TitlePosition.ribbon, paletteColor: _breakingRed),
  ShareTemplate(id: 'ribbon_black', label: 'Breaking Black', titlePosition: TitlePosition.ribbon, paletteColor: _breakingBlack),
  ShareTemplate(id: 'ribbon_navy', label: 'Breaking Navy', titlePosition: TitlePosition.ribbon, paletteColor: _navy),
  ShareTemplate(id: 'card_source', label: 'Editorial', titlePosition: TitlePosition.card),
  ShareTemplate(id: 'card_amber', label: 'Editorial Amber', titlePosition: TitlePosition.card, paletteColor: _amber),
  ShareTemplate(id: 'panel_source', label: 'Bold', titlePosition: TitlePosition.panel),
  ShareTemplate(id: 'panel_mustard', label: 'Bold Mustard', titlePosition: TitlePosition.panel, paletteColor: _mustard),
  ShareTemplate(id: 'panel_forest', label: 'Bold Forest', titlePosition: TitlePosition.panel, paletteColor: _forest),
  ShareTemplate(id: 'spotlight_source', label: 'Spotlight', titlePosition: TitlePosition.spotlight),
  ShareTemplate(id: 'spotlight_maroon', label: 'Spotlight Maroon', titlePosition: TitlePosition.spotlight, paletteColor: _maroon),
  ShareTemplate(id: 'spotlight_plum', label: 'Spotlight Plum', titlePosition: TitlePosition.spotlight, paletteColor: _plum),
  ShareTemplate(id: 'minimal', label: 'Minimal', titlePosition: TitlePosition.minimal),
  ShareTemplate(
    id: 'image',
    label: 'Photo only',
    titlePosition: TitlePosition.minimal,
    showTitle: false,
  ),
];

/// Renders the share card -- a square social template with the article
/// photo, a designed layout (ribbon banner, editorial card, color block,
/// spotlight, or minimal), and a small brand mark -- identically for the
/// live editor preview and the final exported PNG.
class ShareCardRenderer {
  static const double width = 1080;
  static const double height = 1080;
  static const double aspectRatio = 1.0;

  static void paint(
    Canvas canvas,
    Size canvasSize, {
    required ui.Image? image,
    required Color accentColor,
    required String title,
    required String metaText,
    String? category,
    required ShareCardConfig config,
  }) {
    canvas.save();
    canvas.scale(canvasSize.width / width, canvasSize.height / height);
    const bounds = Rect.fromLTWH(0, 0, width, height);
    final hasImage = image != null;
    final palette = config.paletteColor ?? accentColor;

    if (hasImage) {
      _drawImage(canvas, image, bounds, config);
    } else {
      canvas.drawRect(bounds, Paint()..color = palette.withValues(alpha: 0.4));
    }

    if (config.showTitle) {
      switch (config.titlePosition) {
        case TitlePosition.ribbon:
          _drawRibbon(canvas, bounds, title, metaText, category, palette, hasImage: hasImage);
        case TitlePosition.card:
          _drawCard(canvas, bounds, title, metaText, category, palette);
        case TitlePosition.panel:
          _drawPanel(canvas, bounds, title, metaText, category, palette);
        case TitlePosition.spotlight:
          _drawSpotlight(canvas, bounds, title, metaText, category, palette, hasImage: hasImage);
        case TitlePosition.minimal:
          _drawMinimal(canvas, bounds, title, metaText, hasImage: hasImage);
      }
    }

    _drawBrandMark(canvas, bounds, palette);

    canvas.restore();
  }

  static void _drawImage(Canvas canvas, ui.Image image, Rect bounds, ShareCardConfig config) {
    final srcAspect = image.width / image.height;
    final destAspect = bounds.width / bounds.height;

    // Base cover crop (zoom == 1): the largest region matching the card's
    // aspect ratio that still fits fully inside the source image.
    double baseWidth, baseHeight;
    if (srcAspect > destAspect) {
      baseHeight = image.height.toDouble();
      baseWidth = baseHeight * destAspect;
    } else {
      baseWidth = image.width.toDouble();
      baseHeight = baseWidth / destAspect;
    }

    final zoom = config.zoom.clamp(ShareCardConfig.minZoom, ShareCardConfig.maxZoom);
    final srcWidth = baseWidth / zoom;
    final srcHeight = baseHeight / zoom;

    final maxDx = (image.width - srcWidth) / 2;
    final maxDy = (image.height - srcHeight) / 2;
    final centerX = image.width / 2 + config.pan.dx.clamp(-1.0, 1.0) * maxDx;
    final centerY = image.height / 2 + config.pan.dy.clamp(-1.0, 1.0) * maxDy;

    final src = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: srcWidth,
      height: srcHeight,
    );
    canvas.drawImageRect(image, src, bounds, Paint());
  }

  /// Small circular brand mark, top-right -- every template keeps this, the
  /// same way the reference templates keep a logo/handle watermark no
  /// matter how photo-forward the design is.
  static void _drawBrandMark(Canvas canvas, Rect bounds, Color accentColor) {
    const size = 64.0;
    const margin = 36.0;
    final center = Offset(bounds.right - margin - size / 2, bounds.top + margin + size / 2);
    canvas.drawCircle(center, size / 2, Paint()..color = accentColor);
    canvas.drawCircle(
      center,
      size / 2,
      Paint()
        ..color = _white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final mark = TextPainter(
      text: const TextSpan(
        text: 'F',
        style: TextStyle(color: _white, fontSize: 30, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    mark.paint(canvas, Offset(center.dx - mark.width / 2, center.dy - mark.height / 2 - 1));
  }

  static void _drawBottomScrim(Canvas canvas, Rect bounds, {required bool hasImage}) {
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bounds.center.dx, bounds.top),
          Offset(bounds.center.dx, bounds.bottom),
          [const Color(0x00000000), _nearBlack.withValues(alpha: hasImage ? 0.85 : 0.6)],
          const [0.35, 1],
        ),
    );
  }

  /// A diagonal-cut "BREAKING NEWS" ribbon overlapping the photo, plus a
  /// bold headline over a bottom scrim -- the classic breaking-news social
  /// template look.
  static void _drawRibbon(
    Canvas canvas,
    Rect bounds,
    String title,
    String metaText,
    String? category,
    Color bannerColor, {
    required bool hasImage,
  }) {
    _drawBottomScrim(canvas, bounds, hasImage: hasImage);

    final label = (category ?? 'Breaking News').toUpperCase();
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: _white,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 30.0;
    const padV = 16.0;
    const notch = 22.0;
    final bannerWidth = labelPainter.width + padH * 2 + notch;
    final bannerHeight = labelPainter.height + padV * 2;
    const top = 64.0;

    final path = Path()
      ..moveTo(bounds.left, top)
      ..lineTo(bounds.left + bannerWidth, top)
      ..lineTo(bounds.left + bannerWidth - notch, top + bannerHeight)
      ..lineTo(bounds.left, top + bannerHeight)
      ..close();
    canvas.drawShadow(path, _nearBlack, 6, false);
    canvas.drawPath(path, Paint()..color = bannerColor);
    labelPainter.paint(canvas, Offset(bounds.left + padH, top + padV));

    const padding = 48.0;
    final maxWidth = bounds.width - padding * 2;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: _white, fontSize: 50, fontWeight: FontWeight.w800, height: 1.16),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: TextStyle(color: _white.withValues(alpha: 0.85), fontSize: 24, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final metaOffset = Offset(padding, bounds.bottom - padding - metaPainter.height);
    final titleOffset = Offset(padding, metaOffset.dy - 16 - titlePainter.height);
    titlePainter.paint(canvas, titleOffset);
    metaPainter.paint(canvas, metaOffset);
  }

  /// A white editorial card overlapping the bottom of the photo: colored
  /// tag, bold black headline, gray meta line -- plus an outlined category
  /// pill over the photo itself when the article has a category.
  static void _drawCard(
    Canvas canvas,
    Rect bounds,
    String title,
    String metaText,
    String? category,
    Color tagColor,
  ) {
    const padding = 48.0;
    final cardTop = bounds.top + bounds.height * 0.56;
    final cardRect = Rect.fromLTWH(bounds.left, cardTop, bounds.width, bounds.bottom - cardTop);

    canvas.drawRect(
      Rect.fromLTWH(bounds.left, cardTop - 40, bounds.width, 40),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bounds.center.dx, cardTop - 40),
          Offset(bounds.center.dx, cardTop),
          [const Color(0x00000000), const Color(0x2E000000)],
        ),
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(cardRect, topLeft: const Radius.circular(28), topRight: const Radius.circular(28)),
      Paint()..color = _white,
    );

    final tagPainter = TextPainter(
      text: TextSpan(
        text: (category ?? 'Breaking News').toUpperCase(),
        style: const TextStyle(color: _white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.6),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tagRect = Rect.fromLTWH(
      cardRect.left + padding,
      cardRect.top + 30,
      tagPainter.width + 28,
      tagPainter.height + 16,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(tagRect, const Radius.circular(6)), Paint()..color = tagColor);
    tagPainter.paint(canvas, Offset(tagRect.left + 14, tagRect.top + 8));

    final maxTextWidth = cardRect.width - padding * 2;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: _nearBlack, fontSize: 42, fontWeight: FontWeight.w800, height: 1.18),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxTextWidth);
    final titleOffset = Offset(cardRect.left + padding, tagRect.bottom + 20);
    titlePainter.paint(canvas, titleOffset);

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: const TextStyle(color: Color(0xFF6B6B6B), fontSize: 22, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxTextWidth);
    final metaOffset = Offset(cardRect.left + padding, cardRect.bottom - 40 - metaPainter.height);
    final safeMetaOffset =
        Offset(metaOffset.dx, metaOffset.dy < titleOffset.dy + titlePainter.height + 12
            ? titleOffset.dy + titlePainter.height + 12
            : metaOffset.dy);
    metaPainter.paint(canvas, safeMetaOffset);
  }

  /// A solid color block across the bottom third -- headline and meta sit
  /// directly on flat color rather than over the photo, mirroring the
  /// flat-color deck cards in the reference templates.
  static void _drawPanel(
    Canvas canvas,
    Rect bounds,
    String title,
    String metaText,
    String? category,
    Color accentColor,
  ) {
    final bandHeight = bounds.height * 0.36;
    final bandRect = Rect.fromLTWH(bounds.left, bounds.bottom - bandHeight, bounds.width, bandHeight);
    canvas.drawRect(bandRect, Paint()..color = accentColor);

    final textColor = accentColor.computeLuminance() > 0.5 ? _nearBlack : _white;
    const padding = 48.0;
    final maxWidth = bandRect.width - padding * 2;
    double cursorY = bandRect.top + 36;

    if (category != null && category.isNotEmpty) {
      final tagPainter = TextPainter(
        text: TextSpan(
          text: category.toUpperCase(),
          style: TextStyle(
            color: textColor.withValues(alpha: 0.85),
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      tagPainter.paint(canvas, Offset(bandRect.left + padding, cursorY));
      cursorY += tagPainter.height + 14;
    }

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(color: textColor, fontSize: 44, fontWeight: FontWeight.w800, height: 1.15),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    titlePainter.paint(canvas, Offset(bandRect.left + padding, cursorY));

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 22, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    metaPainter.paint(
      canvas,
      Offset(bandRect.left + padding, bandRect.bottom - padding - metaPainter.height),
    );
  }

  /// Full dark overlay with a centered category pill, headline, and meta --
  /// a quote-card / spotlight look.
  static void _drawSpotlight(
    Canvas canvas,
    Rect bounds,
    String title,
    String metaText,
    String? category,
    Color tintColor, {
    required bool hasImage,
  }) {
    canvas.drawRect(bounds, Paint()..color = _nearBlack.withValues(alpha: hasImage ? 0.55 : 0.3));
    canvas.drawRect(bounds, Paint()..color = tintColor.withValues(alpha: hasImage ? 0.28 : 0.4));

    const maxWidth0 = width * 0.78;
    double blockHeight = 0;
    TextPainter? tagPainter;
    if (category != null && category.isNotEmpty) {
      tagPainter = TextPainter(
        text: TextSpan(
          text: category.toUpperCase(),
          style: const TextStyle(color: _white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth0);
      blockHeight += tagPainter.height + 18;
    }

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: _white, fontSize: 48, fontWeight: FontWeight.w800, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 5,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth0);
    blockHeight += titlePainter.height + 18;

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: TextStyle(color: _white.withValues(alpha: 0.8), fontSize: 24, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth0);
    blockHeight += metaPainter.height;

    double cursorY = bounds.center.dy - blockHeight / 2;
    if (tagPainter != null) {
      tagPainter.paint(canvas, Offset(bounds.center.dx - tagPainter.width / 2, cursorY));
      cursorY += tagPainter.height + 18;
    }
    titlePainter.paint(canvas, Offset(bounds.center.dx - titlePainter.width / 2, cursorY));
    cursorY += titlePainter.height + 18;
    metaPainter.paint(canvas, Offset(bounds.center.dx - metaPainter.width / 2, cursorY));
  }

  /// Clean bottom-aligned title over a simple gradient -- the plain,
  /// no-frills option.
  static void _drawMinimal(Canvas canvas, Rect bounds, String title, String metaText, {required bool hasImage}) {
    _drawBottomScrim(canvas, bounds, hasImage: hasImage);

    const padding = 48.0;
    final maxWidth = bounds.width - padding * 2;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: _white, fontSize: 46, fontWeight: FontWeight.w800, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: TextStyle(color: _white.withValues(alpha: 0.85), fontSize: 24, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final metaOffset = Offset(padding, bounds.bottom - padding - metaPainter.height);
    final titleOffset = Offset(padding, metaOffset.dy - 14 - titlePainter.height);
    titlePainter.paint(canvas, titleOffset);
    metaPainter.paint(canvas, metaOffset);
  }
}
