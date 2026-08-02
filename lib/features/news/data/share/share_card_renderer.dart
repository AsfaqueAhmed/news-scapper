import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Which designed layout the card uses. Ignored when
/// [ShareCardConfig.showTitle] is false (photo only, no overlay at all).
enum TitlePosition { ribbon, card, panel, spotlight, minimal, boxedHeadline, updatePill, highlight }

/// Shape of the ribbon template's badge -- the classic diagonal-cut notch,
/// or a plain rounded pill (used by e.g. "Special Report" and "Alert").
enum BannerShape { notch, pill }

/// User-adjustable state for the share card editor: which template layout
/// is active (or whether it's shown at all) and how the photo is framed.
class ShareCardConfig {
  final TitlePosition titlePosition;
  final bool showTitle;

  /// Fixed brand color for this template's banner/panel/pill (e.g. the
  /// "Breaking Red" vs "Breaking Navy" variants). Null falls back to the
  /// article source's own accent color.
  final Color? paletteColor;

  /// Whether the "BREAKING NEWS"/category badge is drawn -- the ribbon
  /// template's banner box, or the card template's tag pill. Ignored by
  /// every other [titlePosition]; the headline/photo/meta layout never
  /// depends on it.
  final bool showBadge;

  /// Shape of the ribbon template's badge. Ignored by every other
  /// [titlePosition].
  final BannerShape bannerShape;

  /// 1.0 = default cover crop, larger zooms in on the photo.
  final double zoom;

  /// Pan of the photo within the crop, each axis in [-1, 1] (0 = centered).
  final Offset pan;

  const ShareCardConfig({
    this.titlePosition = TitlePosition.ribbon,
    this.showTitle = true,
    this.paletteColor,
    this.showBadge = true,
    this.bannerShape = BannerShape.notch,
    this.zoom = 1.0,
    this.pan = Offset.zero,
  });

  static const double minZoom = 1.0;
  static const double maxZoom = 3.0;

  ShareCardConfig copyWith({
    TitlePosition? titlePosition,
    bool? showTitle,
    Color? paletteColor,
    bool? showBadge,
    BannerShape? bannerShape,
    double? zoom,
    Offset? pan,
  }) {
    return ShareCardConfig(
      titlePosition: titlePosition ?? this.titlePosition,
      showTitle: showTitle ?? this.showTitle,
      paletteColor: paletteColor ?? this.paletteColor,
      showBadge: showBadge ?? this.showBadge,
      bannerShape: bannerShape ?? this.bannerShape,
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
  final BannerShape bannerShape;

  const ShareTemplate({
    required this.id,
    required this.label,
    required this.titlePosition,
    this.showTitle = true,
    this.paletteColor,
    this.bannerShape = BannerShape.notch,
  });
}

const _white = Color(0xFFFFFFFF);
const _nearBlack = Color(0xFF15151A);
const _breakingRed = Color(0xFFE0272B);
const _khaki = Color(0xFFC7B693);
const _alertYellow = Color(0xFFE8B923);

/// Kept intentionally short -- more templates (and their palette colors)
/// get added back here over time.
const List<ShareTemplate> shareTemplates = [
  ShareTemplate(id: 'ribbon_red', label: 'Breaking Red', titlePosition: TitlePosition.ribbon, paletteColor: _breakingRed),
  ShareTemplate(id: 'card_source', label: 'Editorial', titlePosition: TitlePosition.card),
  ShareTemplate(id: 'spotlight_source', label: 'Spotlight', titlePosition: TitlePosition.spotlight),
  ShareTemplate(
    id: 'image',
    label: 'Photo only',
    titlePosition: TitlePosition.minimal,
    showTitle: false,
  ),
  ShareTemplate(id: 'panel_khaki', label: 'Field Report', titlePosition: TitlePosition.panel, paletteColor: _khaki),
  ShareTemplate(
    id: 'ribbon_pill_red',
    label: 'Special Report',
    titlePosition: TitlePosition.ribbon,
    paletteColor: _breakingRed,
    bannerShape: BannerShape.pill,
  ),
  ShareTemplate(
    id: 'ribbon_pill_yellow',
    label: 'Alert',
    titlePosition: TitlePosition.ribbon,
    paletteColor: _alertYellow,
    bannerShape: BannerShape.pill,
  ),
  ShareTemplate(id: 'boxed_headline', label: 'Impact', titlePosition: TitlePosition.boxedHeadline, paletteColor: _breakingRed),
  ShareTemplate(id: 'update_pill', label: 'Update', titlePosition: TitlePosition.updatePill, paletteColor: _breakingRed),
  ShareTemplate(id: 'highlight', label: 'Highlight', titlePosition: TitlePosition.highlight, paletteColor: _breakingRed),
];

/// Renders the share card -- a square social template with the article
/// photo, a designed layout (ribbon banner, editorial card, color block,
/// spotlight, or minimal), and a small brand mark -- identically for the
/// live editor preview and the final exported PNG.
class ShareCardRenderer {
  static const double width = 1080;
  static const double height = 1080;
  static const double aspectRatio = 1.0;

  static const _brandLogoAssetPath = 'assets/branding/flashbangla_logo.png';
  static Future<ui.Image>? _brandLogoFuture;

  /// Loads (and caches) the brand logo used in the corner mark. Callers
  /// await this once before painting, since [paint] itself is synchronous.
  static Future<ui.Image> loadBrandLogo() {
    return _brandLogoFuture ??= _decodeAsset(_brandLogoAssetPath);
  }

  static Future<ui.Image> _decodeAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static void paint(
    Canvas canvas,
    Size canvasSize, {
    required ui.Image? image,
    required ui.Image? logo,
    required Color accentColor,
    required String title,
    String? description,
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
          _drawRibbon(canvas, bounds, title, metaText, category, palette,
              hasImage: hasImage, showBadge: config.showBadge, bannerShape: config.bannerShape);
        case TitlePosition.card:
          _drawCard(canvas, bounds, title, description, metaText, category, palette,
              showBadge: config.showBadge);
        case TitlePosition.panel:
          _drawPanel(canvas, bounds, title, description, metaText, category, palette,
              showBadge: config.showBadge);
        case TitlePosition.spotlight:
          _drawSpotlight(canvas, bounds, title, metaText, category, palette, hasImage: hasImage);
        case TitlePosition.minimal:
          _drawMinimal(canvas, bounds, title, metaText, hasImage: hasImage);
        case TitlePosition.boxedHeadline:
          _drawBoxedHeadline(canvas, bounds, title, description, metaText, category, palette,
              hasImage: hasImage, showBadge: config.showBadge);
        case TitlePosition.updatePill:
          _drawUpdatePill(canvas, bounds, title, metaText, category, palette,
              hasImage: hasImage, showBadge: config.showBadge);
        case TitlePosition.highlight:
          _drawHighlight(canvas, bounds, title, description, metaText, palette, logo, hasImage: hasImage);
      }
    }

    if (config.titlePosition != TitlePosition.highlight) {
      _drawBrandMark(canvas, bounds, palette, logo);
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

  /// Draws [logo] clipped to a circle at [center]/[radius] plus a white
  /// stroke ring; falls back to a colored circle with a plain "F" mark if
  /// [logo] is null (e.g. briefly, before it's loaded).
  static void _drawCircularLogo(Canvas canvas, Offset center, double radius, ui.Image? logo,
      {required Color fallbackColor}) {
    final circleRect = Rect.fromCircle(center: center, radius: radius);

    if (logo != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(circleRect));
      final logoSize = logo.width < logo.height ? logo.width.toDouble() : logo.height.toDouble();
      final src = Rect.fromCenter(
        center: Offset(logo.width / 2, logo.height / 2),
        width: logoSize,
        height: logoSize,
      );
      canvas.drawImageRect(logo, src, circleRect, Paint());
      canvas.restore();
    } else {
      canvas.drawCircle(center, radius, Paint()..color = fallbackColor);
      final mark = TextPainter(
        text: const TextSpan(
          text: 'F',
          style: TextStyle(color: _white, fontSize: 30, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      mark.paint(canvas, Offset(center.dx - mark.width / 2, center.dy - mark.height / 2 - 1));
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  /// Small circular brand mark, top-right -- every template keeps this
  /// (except [TitlePosition.highlight], which draws its own large logo
  /// instead), the same way the reference templates keep a logo/handle
  /// watermark no matter how photo-forward the design is.
  static void _drawBrandMark(Canvas canvas, Rect bounds, Color accentColor, ui.Image? logo) {
    const size = 64.0;
    const margin = 36.0;
    final center = Offset(bounds.right - margin - size / 2, bounds.top + margin + size / 2);
    _drawCircularLogo(canvas, center, size / 2, logo, fallbackColor: accentColor);
  }

  /// Draws a filled, fully-rounded pill with a bold white uppercase label,
  /// anchored either top-left at [anchor] or centered on it. Returns the
  /// drawn rect so callers can lay out content relative to it.
  static Rect _drawPill(Canvas canvas, String label, Color color, {required Offset anchor, required bool centered}) {
    final painter = TextPainter(
      text: TextSpan(
        text: label.toUpperCase(),
        style: const TextStyle(color: _white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 26.0;
    const padV = 14.0;
    final w = painter.width + padH * 2;
    final h = painter.height + padV * 2;
    final rect =
        centered ? Rect.fromCenter(center: anchor, width: w, height: h) : Rect.fromLTWH(anchor.dx, anchor.dy, w, h);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));

    canvas.drawShadow(Path()..addRRect(rrect), _nearBlack, 6, false);
    canvas.drawRRect(rrect, Paint()..color = color);
    painter.paint(canvas, Offset(rect.left + padH, rect.top + padV));
    return rect;
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

  /// A "BREAKING NEWS" banner overlapping the photo -- either the classic
  /// diagonal-cut notch, or a plain rounded pill -- plus a bold headline
  /// over a bottom scrim.
  static void _drawRibbon(
    Canvas canvas,
    Rect bounds,
    String title,
    String metaText,
    String? category,
    Color bannerColor, {
    required bool hasImage,
    required bool showBadge,
    required BannerShape bannerShape,
  }) {
    _drawBottomScrim(canvas, bounds, hasImage: hasImage);
    const padding = 48.0;
    const top = 64.0;

    if (showBadge) {
      final label = category ?? 'Breaking News';
      if (bannerShape == BannerShape.pill) {
        _drawPill(canvas, label, bannerColor, anchor: Offset(bounds.left + padding, top), centered: false);
      } else {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: label.toUpperCase(),
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

        final path = Path()
          ..moveTo(bounds.left, top)
          ..lineTo(bounds.left + bannerWidth, top)
          ..lineTo(bounds.left + bannerWidth - notch, top + bannerHeight)
          ..lineTo(bounds.left, top + bannerHeight)
          ..close();
        canvas.drawShadow(path, _nearBlack, 6, false);
        canvas.drawPath(path, Paint()..color = bannerColor);
        labelPainter.paint(canvas, Offset(bounds.left + padH, top + padV));
      }
    }

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
  /// category tag (hidden when [showBadge] is false), bold black headline,
  /// a short description, gray meta line. The card's height tracks exactly
  /// how much its content needs (title and description each cap at a few
  /// lines), rather than a fixed fraction of the photo.
  static void _drawCard(
    Canvas canvas,
    Rect bounds,
    String title,
    String? description,
    String metaText,
    String? category,
    Color tagColor, {
    required bool showBadge,
  }) {
    const padding = 48.0;
    const topInset = 30.0;
    const afterTagGap = 20.0;
    const afterTitleGap = 16.0;
    const afterDescriptionGap = 14.0;
    const bottomInset = 40.0;
    final maxTextWidth = bounds.width - padding * 2;

    TextPainter? tagPainter;
    double tagBoxHeight = 0;
    if (showBadge) {
      tagPainter = TextPainter(
        text: TextSpan(
          text: (category ?? 'Breaking News').toUpperCase(),
          style: const TextStyle(color: _white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.6),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tagBoxHeight = tagPainter.height + 16;
    }

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: _nearBlack, fontSize: 42, fontWeight: FontWeight.w800, height: 1.18),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxTextWidth);

    TextPainter? descriptionPainter;
    if (description != null && description.isNotEmpty) {
      descriptionPainter = TextPainter(
        text: TextSpan(
          text: description,
          style: const TextStyle(color: Color(0xFF4A4A4A), fontSize: 26, fontWeight: FontWeight.w500, height: 1.32),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: maxTextWidth);
    }

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: const TextStyle(color: Color(0xFF6B6B6B), fontSize: 22, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxTextWidth);

    var contentHeight = topInset;
    if (showBadge) {
      contentHeight += tagBoxHeight + afterTagGap;
    }
    contentHeight += titlePainter.height;
    if (descriptionPainter != null) {
      contentHeight += afterTitleGap + descriptionPainter.height;
    }
    contentHeight += afterDescriptionGap + metaPainter.height + bottomInset;

    final cardTop = bounds.bottom - contentHeight;
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

    var cursorY = cardRect.top + topInset;
    if (showBadge && tagPainter != null) {
      final tagRect = Rect.fromLTWH(cardRect.left + padding, cursorY, tagPainter.width + 28, tagBoxHeight);
      canvas.drawRRect(RRect.fromRectAndRadius(tagRect, const Radius.circular(6)), Paint()..color = tagColor);
      tagPainter.paint(canvas, Offset(tagRect.left + 14, tagRect.top + 8));
      cursorY = tagRect.bottom + afterTagGap;
    }
    titlePainter.paint(canvas, Offset(cardRect.left + padding, cursorY));
    cursorY += titlePainter.height;

    if (descriptionPainter != null) {
      cursorY += afterTitleGap;
      descriptionPainter.paint(canvas, Offset(cardRect.left + padding, cursorY));
      cursorY += descriptionPainter.height;
    }

    cursorY += afterDescriptionGap;
    metaPainter.paint(canvas, Offset(cardRect.left + padding, cursorY));
  }

  /// A solid color block at the bottom -- headline and description sit
  /// directly on flat color rather than over the photo. When [showBadge]
  /// is true, a dark badge pill floats over the photo above the block
  /// (independent of the block's own color, so it stays legible no matter
  /// which palette color the block uses). The block's height tracks its
  /// content, same technique as [_drawCard].
  static void _drawPanel(
    Canvas canvas,
    Rect bounds,
    String title,
    String? description,
    String metaText,
    String? category,
    Color accentColor, {
    required bool showBadge,
  }) {
    const padding = 48.0;
    const topInset = 36.0;
    const afterTitleGap = 14.0;
    const afterDescriptionGap = 14.0;
    const bottomInset = 40.0;
    final maxWidth = bounds.width - padding * 2;
    final textColor = accentColor.computeLuminance() > 0.5 ? _nearBlack : _white;

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(color: textColor, fontSize: 44, fontWeight: FontWeight.w800, height: 1.15),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    TextPainter? descriptionPainter;
    if (description != null && description.isNotEmpty) {
      descriptionPainter = TextPainter(
        text: TextSpan(
          text: description,
          style: TextStyle(color: textColor.withValues(alpha: 0.85), fontSize: 24, fontWeight: FontWeight.w500, height: 1.3),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
    }

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 22, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    var bandHeight = topInset + titlePainter.height;
    if (descriptionPainter != null) {
      bandHeight += afterTitleGap + descriptionPainter.height;
    }
    bandHeight += afterDescriptionGap + metaPainter.height + bottomInset;

    final bandRect = Rect.fromLTWH(bounds.left, bounds.bottom - bandHeight, bounds.width, bandHeight);
    canvas.drawRect(bandRect, Paint()..color = accentColor);

    if (showBadge) {
      _drawPill(canvas, category ?? 'Breaking News', _nearBlack.withValues(alpha: 0.85),
          anchor: Offset(bounds.left + padding, 64), centered: false);
    }

    var cursorY = bandRect.top + topInset;
    titlePainter.paint(canvas, Offset(bandRect.left + padding, cursorY));
    cursorY += titlePainter.height;

    if (descriptionPainter != null) {
      cursorY += afterTitleGap;
      descriptionPainter.paint(canvas, Offset(bandRect.left + padding, cursorY));
      cursorY += descriptionPainter.height;
    }

    cursorY += afterDescriptionGap;
    metaPainter.paint(canvas, Offset(bandRect.left + padding, cursorY));
  }

  /// A solid-color rounded box floating over the lower photo (inset from
  /// both edges, unlike [_drawPanel]'s edge-to-edge band), sized to fit
  /// just the headline. A dark badge pill sits above it on the photo; an
  /// optional 2-line description and the meta line sit below it, also
  /// directly on the photo over a bottom scrim.
  static void _drawBoxedHeadline(
    Canvas canvas,
    Rect bounds,
    String title,
    String? description,
    String metaText,
    String? category,
    Color boxColor, {
    required bool hasImage,
    required bool showBadge,
  }) {
    _drawBottomScrim(canvas, bounds, hasImage: hasImage);

    const padding = 48.0;
    const boxPadding = 32.0;
    const afterBoxGap = 20.0;
    const afterDescriptionGap = 14.0;
    const bottomInset = 40.0;
    final maxWidth = bounds.width - padding * 2;
    final maxBoxTextWidth = maxWidth - boxPadding * 2;

    if (showBadge) {
      _drawPill(canvas, category ?? 'Breaking News', _nearBlack, anchor: Offset(padding, 64), centered: false);
    }

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: _white, fontSize: 42, fontWeight: FontWeight.w800, height: 1.18),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxBoxTextWidth);
    final boxHeight = titlePainter.height + boxPadding * 2;

    TextPainter? descriptionPainter;
    if (description != null && description.isNotEmpty) {
      descriptionPainter = TextPainter(
        text: TextSpan(
          text: description,
          style: TextStyle(color: _white.withValues(alpha: 0.85), fontSize: 24, fontWeight: FontWeight.w500, height: 1.3),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
    }

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: TextStyle(color: _white.withValues(alpha: 0.85), fontSize: 24, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    var stackHeight = boxHeight + afterBoxGap;
    if (descriptionPainter != null) {
      stackHeight += descriptionPainter.height + afterDescriptionGap;
    }
    stackHeight += metaPainter.height;

    var cursorY = bounds.bottom - bottomInset - stackHeight;
    final boxRect = Rect.fromLTWH(padding, cursorY, maxWidth, boxHeight);
    canvas.drawRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(20)), Paint()..color = boxColor);
    titlePainter.paint(canvas, Offset(boxRect.left + boxPadding, boxRect.top + boxPadding));
    cursorY = boxRect.bottom + afterBoxGap;

    if (descriptionPainter != null) {
      descriptionPainter.paint(canvas, Offset(padding, cursorY));
      cursorY += descriptionPainter.height + afterDescriptionGap;
    }
    metaPainter.paint(canvas, Offset(padding, cursorY));
  }

  /// A pill badge centered in the upper-middle of the photo, with the bold
  /// headline and meta line left-aligned below it over a bottom scrim. No
  /// description -- keeps this layout visually distinct from the other
  /// description-using templates.
  static void _drawUpdatePill(
    Canvas canvas,
    Rect bounds,
    String title,
    String metaText,
    String? category,
    Color pillColor, {
    required bool hasImage,
    required bool showBadge,
  }) {
    _drawBottomScrim(canvas, bounds, hasImage: hasImage);

    if (showBadge) {
      _drawPill(canvas, category ?? 'News Update', pillColor,
          anchor: Offset(bounds.center.dx, bounds.top + bounds.height * 0.3), centered: true);
    }

    const padding = 48.0;
    final maxWidth = bounds.width - padding * 2;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: _white, fontSize: 44, fontWeight: FontWeight.w800, height: 1.18),
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

  /// Full-bleed photo, no category badge: the headline is drawn with a
  /// colored "highlighter" bar behind each wrapped line (via
  /// [TextPainter.computeLineMetrics]), followed by an optional
  /// description and the meta line. Instead of the usual small top-right
  /// corner mark, the actual logo is shown large and centered at the
  /// bottom -- [ShareCardRenderer.paint] skips the corner mark for this
  /// [TitlePosition] to avoid showing the logo twice.
  static void _drawHighlight(
    Canvas canvas,
    Rect bounds,
    String title,
    String? description,
    String metaText,
    Color highlightColor,
    ui.Image? logo, {
    required bool hasImage,
  }) {
    _drawBottomScrim(canvas, bounds, hasImage: hasImage);

    const padding = 48.0;
    const logoSize = 90.0;
    const afterTitleGap = 16.0;
    const afterDescriptionGap = 16.0;
    const beforeLogoGap = 28.0;
    const bottomInset = 44.0;
    final maxWidth = bounds.width - padding * 2;

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(color: _white, fontSize: 46, fontWeight: FontWeight.w800, height: 1.3),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    TextPainter? descriptionPainter;
    if (description != null && description.isNotEmpty) {
      descriptionPainter = TextPainter(
        text: TextSpan(
          text: description,
          style: TextStyle(color: _white.withValues(alpha: 0.85), fontSize: 26, fontWeight: FontWeight.w500, height: 1.32),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
    }

    final metaPainter = TextPainter(
      text: TextSpan(
        text: metaText,
        style: TextStyle(color: _white.withValues(alpha: 0.7), fontSize: 22, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    var stackHeight = titlePainter.height;
    if (descriptionPainter != null) {
      stackHeight += afterTitleGap + descriptionPainter.height;
    }
    stackHeight += afterDescriptionGap + metaPainter.height + beforeLogoGap + logoSize + bottomInset;

    var cursorY = bounds.bottom - stackHeight;

    for (final line in titlePainter.computeLineMetrics()) {
      final lineTop = line.baseline - line.ascent;
      final lineRect = Rect.fromLTWH(
        padding + line.left - 10,
        cursorY + lineTop + 4,
        line.width + 20,
        line.height - 6,
      );
      canvas.drawRect(lineRect, Paint()..color = highlightColor);
    }
    titlePainter.paint(canvas, Offset(padding, cursorY));
    cursorY += titlePainter.height;

    if (descriptionPainter != null) {
      cursorY += afterTitleGap;
      descriptionPainter.paint(canvas, Offset(padding, cursorY));
      cursorY += descriptionPainter.height;
    }

    cursorY += afterDescriptionGap;
    metaPainter.paint(canvas, Offset(padding, cursorY));
    cursorY += metaPainter.height + beforeLogoGap;

    final logoCenter = Offset(bounds.center.dx, cursorY + logoSize / 2);
    _drawCircularLogo(canvas, logoCenter, logoSize / 2, logo, fallbackColor: highlightColor);
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
