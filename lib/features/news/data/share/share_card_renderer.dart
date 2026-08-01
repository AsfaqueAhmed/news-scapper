import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Where the title/source overlay sits on the card. Ignored when
/// [ShareCardConfig.showTitle] is false. [TitlePosition.newsCard] is a
/// distinct layout -- a white "breaking news" card overlapping the bottom
/// of the photo -- rather than a gradient + overlaid text position.
enum TitlePosition { bottom, top, left, right, center, newsCard }

/// User-adjustable state for the share card editor: where the title sits
/// (or whether it's shown at all) and how the photo is framed.
class ShareCardConfig {
  final TitlePosition titlePosition;
  final bool showTitle;

  /// 1.0 = default cover crop, larger zooms in on the photo.
  final double zoom;

  /// Pan of the photo within the crop, each axis in [-1, 1] (0 = centered).
  final Offset pan;

  const ShareCardConfig({
    this.titlePosition = TitlePosition.bottom,
    this.showTitle = true,
    this.zoom = 1.0,
    this.pan = Offset.zero,
  });

  static const double minZoom = 1.0;
  static const double maxZoom = 3.0;

  ShareCardConfig copyWith({
    TitlePosition? titlePosition,
    bool? showTitle,
    double? zoom,
    Offset? pan,
  }) {
    return ShareCardConfig(
      titlePosition: titlePosition ?? this.titlePosition,
      showTitle: showTitle ?? this.showTitle,
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

  const ShareTemplate({
    required this.id,
    required this.label,
    required this.titlePosition,
    this.showTitle = true,
  });
}

const List<ShareTemplate> shareTemplates = [
  ShareTemplate(id: 'news_card', label: 'Breaking', titlePosition: TitlePosition.newsCard),
  ShareTemplate(id: 'bottom', label: 'Bottom', titlePosition: TitlePosition.bottom),
  ShareTemplate(id: 'top', label: 'Top', titlePosition: TitlePosition.top),
  ShareTemplate(id: 'left', label: 'Left', titlePosition: TitlePosition.left),
  ShareTemplate(id: 'right', label: 'Right', titlePosition: TitlePosition.right),
  ShareTemplate(id: 'center', label: 'Center', titlePosition: TitlePosition.center),
  ShareTemplate(
    id: 'image',
    label: 'Image only',
    titlePosition: TitlePosition.bottom,
    showTitle: false,
  ),
];

/// Renders the share card -- article photo, optional gradient scrim, and
/// title/source overlay -- the same way for the live editor preview and the
/// final exported PNG, so what's on screen is exactly what gets shared.
class ShareCardRenderer {
  static const double width = 1200;
  static const double height = 675;
  static const double aspectRatio = width / height;

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

    if (image != null) {
      _drawImage(canvas, image, bounds, config);
    } else {
      canvas.drawRect(bounds, Paint()..color = accentColor.withValues(alpha: 0.35));
    }

    if (config.showTitle) {
      if (config.titlePosition == TitlePosition.newsCard) {
        _drawNewsCard(canvas, bounds, title, metaText, category, accentColor);
      } else {
        _drawScrim(canvas, bounds, config.titlePosition, hasImage: image != null);
        _drawText(canvas, bounds, title, metaText, config.titlePosition);
      }
    }

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

  static void _drawScrim(Canvas canvas, Rect bounds, TitlePosition position, {required bool hasImage}) {
    final alpha = hasImage ? 0.78 : 0.55;
    const transparent = Color(0x00000000);
    final dark = const Color(0xFF000000).withValues(alpha: alpha);

    switch (position) {
      case TitlePosition.bottom:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(bounds.center.dx, bounds.top),
              Offset(bounds.center.dx, bounds.bottom),
              [transparent, dark],
              const [0.3, 1],
            ),
        );
      case TitlePosition.top:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(bounds.center.dx, bounds.bottom),
              Offset(bounds.center.dx, bounds.top),
              [transparent, dark],
              const [0.3, 1],
            ),
        );
      case TitlePosition.left:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(bounds.right, bounds.center.dy),
              Offset(bounds.left, bounds.center.dy),
              [transparent, dark],
              const [0.32, 1],
            ),
        );
      case TitlePosition.right:
        canvas.drawRect(
          bounds,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(bounds.left, bounds.center.dy),
              Offset(bounds.right, bounds.center.dy),
              [transparent, dark],
              const [0.32, 1],
            ),
        );
      case TitlePosition.center:
        canvas.drawRect(bounds, Paint()..color = const Color(0xFF000000).withValues(alpha: alpha * 0.65));
      case TitlePosition.newsCard:
        break; // Drawn by _drawNewsCard instead.
    }
  }

  /// A white card overlapping the bottom of the photo, mimicking a
  /// "breaking news" social template: colored tag, bold black headline,
  /// and a small source/time line -- plus an outlined category pill over
  /// the photo itself when the article has a category.
  static void _drawNewsCard(
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

    // Soften the seam between photo and card before the rounded corners.
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
      Paint()..color = const Color(0xFFFFFFFF),
    );

    final tagPainter = TextPainter(
      text: const TextSpan(
        text: 'BREAKING NEWS',
        style: TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tagRect = Rect.fromLTWH(
      cardRect.left + padding,
      cardRect.top + 30,
      tagPainter.width + 28,
      tagPainter.height + 16,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tagRect, const Radius.circular(6)),
      Paint()..color = tagColor,
    );
    tagPainter.paint(canvas, Offset(tagRect.left + 14, tagRect.top + 8));

    final maxTextWidth = cardRect.width - padding * 2;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Color(0xFF161616),
          fontSize: 42,
          fontWeight: FontWeight.w800,
          height: 1.18,
        ),
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
    // Never overlap the title if it wrapped to 3 lines on a short card.
    final safeMetaOffset = Offset(metaOffset.dx, math.max(metaOffset.dy, titleOffset.dy + titlePainter.height + 12));
    metaPainter.paint(canvas, safeMetaOffset);

    if (category != null && category.isNotEmpty) {
      _drawOutlinedPill(canvas, bounds, category);
    }
  }

  static void _drawOutlinedPill(Canvas canvas, Rect bounds, String label) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 18.0;
    const paddingV = 10.0;
    const margin = 32.0;
    final pillRect = Rect.fromLTWH(
      bounds.right - margin - textPainter.width - paddingH * 2,
      bounds.top + margin,
      textPainter.width + paddingH * 2,
      textPainter.height + paddingV * 2,
    );
    final pillRRect = RRect.fromRectAndRadius(pillRect, const Radius.circular(8));
    canvas.drawRRect(pillRRect, Paint()..color = const Color(0x33000000));
    canvas.drawRRect(
      pillRRect,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    textPainter.paint(canvas, Offset(pillRect.left + paddingH, pillRect.top + paddingV));
  }

  static void _drawText(Canvas canvas, Rect bounds, String title, String metaText, TitlePosition position) {
    const padding = 48.0;
    const gap = 14.0;
    final isSide = position == TitlePosition.left || position == TitlePosition.right;

    final maxWidth = switch (position) {
      TitlePosition.left || TitlePosition.right => bounds.width * 0.56 - padding * 1.5,
      TitlePosition.center => bounds.width * 0.8,
      TitlePosition.bottom || TitlePosition.top || TitlePosition.newsCard => bounds.width - padding * 2,
    };
    final align = switch (position) {
      TitlePosition.center => TextAlign.center,
      TitlePosition.right => TextAlign.right,
      _ => TextAlign.left,
    };

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 46,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: isSide || position == TitlePosition.center ? 5 : 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: TextStyle(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);

    final blockHeight = titlePainter.height + gap + metaPainter.height;
    final Offset titleOffset;
    final Offset metaOffset;
    switch (position) {
      case TitlePosition.bottom:
        metaOffset = Offset(padding, bounds.bottom - padding - metaPainter.height);
        titleOffset = Offset(padding, metaOffset.dy - gap - titlePainter.height);
      case TitlePosition.top:
        titleOffset = Offset(padding, bounds.top + padding);
        metaOffset = Offset(padding, titleOffset.dy + titlePainter.height + gap);
      case TitlePosition.left:
        final top = bounds.center.dy - blockHeight / 2;
        titleOffset = Offset(padding, top);
        metaOffset = Offset(padding, top + titlePainter.height + gap);
      case TitlePosition.right:
        final top = bounds.center.dy - blockHeight / 2;
        titleOffset = Offset(bounds.right - padding - titlePainter.width, top);
        metaOffset = Offset(bounds.right - padding - metaPainter.width, top + titlePainter.height + gap);
      case TitlePosition.center:
        final top = bounds.center.dy - blockHeight / 2;
        titleOffset = Offset(bounds.center.dx - titlePainter.width / 2, top);
        metaOffset = Offset(bounds.center.dx - metaPainter.width / 2, top + titlePainter.height + gap);
      case TitlePosition.newsCard:
        // Unreachable: paint() routes newsCard through _drawNewsCard instead.
        metaOffset = Offset(padding, bounds.bottom - padding - metaPainter.height);
        titleOffset = Offset(padding, metaOffset.dy - gap - titlePainter.height);
    }

    titlePainter.paint(canvas, titleOffset);
    metaPainter.paint(canvas, metaOffset);
  }
}
