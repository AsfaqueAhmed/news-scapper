import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_format.dart';
import '../models/article_model.dart';

/// Wraps the native share sheet, sharing a composed card image -- the
/// article's photo with a gradient scrim and the title/source overlaid in
/// white, mirroring the "Top story" hero card in the dashboard -- instead
/// of a bare photo or a plain text link.
///
/// Auto-posting to an external destination (e.g. a Facebook Page) is not
/// implemented: it needs a Facebook Page access token and app review, which
/// are out of scope for now. `NewsPrefsDataSource.setLastAutoShared` is
/// wired up and ready for whenever that's added.
class ShareDataSource {
  static const _cacheDirName = 'share_cache';
  static const _maxCacheAge = Duration(days: 1);
  static const _cardWidth = 1200.0;
  static const _cardHeight = 675.0;

  final http.Client _client;

  ShareDataSource(this._client);

  Future<void> shareArticle(ArticleModel article) async {
    final text = '${article.title}\n${article.link}';
    final cardPath = await _cachedCardPath(article);

    await SharePlus.instance.share(
      cardPath != null
          ? ShareParams(text: text, files: [XFile(cardPath)])
          : ShareParams(text: text),
    );
  }

  /// Renders (or reuses a cached render of) the share card and prunes
  /// anything older than a day from that same cache. Returns null --
  /// falling back to a text-only share -- if rendering fails.
  Future<String?> _cachedCardPath(ArticleModel article) async {
    final dir = await _cacheDir();
    await _pruneOldFiles(dir);

    final path = '${dir.path}/${article.id}.png';
    final file = File(path);
    if (await file.exists()) return path;

    try {
      final imageBytes = await _downloadImage(article.imageUrl);
      final png = await _composeCard(article, imageBytes);
      await file.writeAsBytes(png);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _downloadImage(String? imageUrl) async {
    if (imageUrl == null) return null;
    try {
      final response =
          await _client.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  Future<Uint8List> composeCardForTesting(ArticleModel article, Uint8List? imageBytes) =>
      _composeCard(article, imageBytes);

  Future<Uint8List> _composeCard(ArticleModel article, Uint8List? imageBytes) async {
    final accent = sourceAccent(article.sourceId);
    final hasImage = imageBytes != null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _cardWidth, _cardHeight));
    const bounds = Rect.fromLTWH(0, 0, _cardWidth, _cardHeight);

    if (hasImage) {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      _drawImageCover(canvas, frame.image, bounds);
    } else {
      canvas.drawRect(bounds, Paint()..color = accent.withValues(alpha: 0.35));
    }

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(_cardWidth / 2, 0),
          const Offset(_cardWidth / 2, _cardHeight),
          [
            const Color(0x00000000),
            Color(0xFF000000).withValues(alpha: hasImage ? 0.8 : 0.6),
          ],
          const [0.3, 1],
        ),
    );

    const horizontalPadding = 48.0;
    const maxTextWidth = _cardWidth - horizontalPadding * 2;

    final meta = TextPainter(
      text: TextSpan(
        text: '${article.sourceName} · ${relativeTime(article.pubDate)}',
        style: TextStyle(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxTextWidth);

    final title = TextPainter(
      text: TextSpan(
        text: article.title,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 46,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxTextWidth);

    const bottomPadding = 40.0;
    final metaOffset = Offset(horizontalPadding, _cardHeight - bottomPadding - meta.height);
    final titleOffset = Offset(
      horizontalPadding,
      metaOffset.dy - 14 - title.height,
    );
    title.paint(canvas, titleOffset);
    meta.paint(canvas, metaOffset);

    final picture = recorder.endRecording();
    final image = await picture.toImage(_cardWidth.toInt(), _cardHeight.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _drawImageCover(Canvas canvas, ui.Image image, Rect dest) {
    final srcAspect = image.width / image.height;
    final destAspect = dest.width / dest.height;
    final Rect src;
    if (srcAspect > destAspect) {
      final srcWidth = image.height * destAspect;
      final dx = (image.width - srcWidth) / 2;
      src = Rect.fromLTWH(dx, 0, srcWidth, image.height.toDouble());
    } else {
      final srcHeight = image.width / destAspect;
      final dy = (image.height - srcHeight) / 2;
      src = Rect.fromLTWH(0, dy, image.width.toDouble(), srcHeight);
    }
    canvas.drawImageRect(image, src, dest, Paint());
  }

  Future<Directory> _cacheDir() async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/$_cacheDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _pruneOldFiles(Directory dir) async {
    final cutoff = DateTime.now().subtract(_maxCacheAge);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final modified = await entity.lastModified();
      if (modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }
}
