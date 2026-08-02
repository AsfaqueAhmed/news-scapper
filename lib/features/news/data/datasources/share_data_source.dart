import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show Canvas, Rect, Size;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_format.dart';
import '../models/article_model.dart';
import '../share/share_card_renderer.dart';

/// Downloads article images, composes the share card (photo + title
/// overlay, per the caller's [ShareCardConfig]), and drives the native
/// share sheet.
///
/// Auto-posting to an external destination (e.g. a Facebook Page) is not
/// implemented: it needs a Facebook Page access token and app review, which
/// are out of scope for now. `NewsPrefsDataSource.setLastAutoShared` is
/// wired up and ready for whenever that's added.
class ShareDataSource {
  static const _cacheDirName = 'share_cache';
  static const _maxCacheAge = Duration(days: 1);

  final http.Client _client;

  ShareDataSource(this._client);

  /// Downloads (or reuses a cached copy of) an article's source image.
  Future<ui.Image?> loadImage(String? imageUrl) async {
    final bytes = await _downloadImage(imageUrl);
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Renders the share card for [article] with the given [config] and
  /// returns it as PNG bytes.
  Future<Uint8List> composeCard(
    ArticleModel article,
    ui.Image? image,
    ShareCardConfig config,
  ) async {
    final logo = await ShareCardRenderer.loadBrandLogo();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, ShareCardRenderer.width, ShareCardRenderer.height));
    ShareCardRenderer.paint(
      canvas,
      const Size(ShareCardRenderer.width, ShareCardRenderer.height),
      image: image,
      logo: logo,
      accentColor: sourceAccent(article.sourceId),
      title: article.title,
      description: article.description,
      metaText: '${article.sourceName} · ${relativeTime(article.pubDate)}',
      category: article.category,
      config: config,
    );
    final picture = recorder.endRecording();
    final rendered =
        await picture.toImage(ShareCardRenderer.width.toInt(), ShareCardRenderer.height.toInt());
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Opens the native share sheet with the composed card attached,
  /// alongside the title and link as text. On native platforms the card is
  /// written to the temp cache first (and reused if shared again); the web
  /// has no filesystem to cache into, so there [pngBytes] is attached
  /// directly.
  Future<void> shareComposedCard(ArticleModel article, Uint8List pngBytes) async {
    final fileName = '${article.id}_card.png';
    final file = kIsWeb
        ? XFile.fromData(pngBytes, name: fileName, mimeType: 'image/png')
        : await _writeToCache(fileName, pngBytes);

    await SharePlus.instance.share(
      ShareParams(text: '${article.title}\n${article.link}', files: [file]),
    );
  }

  Future<XFile> _writeToCache(String fileName, Uint8List bytes) async {
    final dir = await _cacheDir();
    await _pruneOldFiles(dir);
    final path = '${dir.path}/$fileName';
    await File(path).writeAsBytes(bytes);
    return XFile(path);
  }

  Future<Uint8List?> _downloadImage(String? imageUrl) async {
    if (imageUrl == null) return null;

    // The web has no filesystem to cache into, so just fetch fresh each time.
    if (kIsWeb) {
      try {
        final response =
            await _client.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 15));
        return response.statusCode == 200 ? response.bodyBytes : null;
      } catch (_) {
        return null;
      }
    }

    final dir = await _cacheDir();
    final path = '${dir.path}/${_hash(imageUrl)}${_extensionFor(imageUrl)}';
    final file = File(path);
    if (await file.exists()) return file.readAsBytes();

    try {
      final response =
          await _client.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      await file.writeAsBytes(response.bodyBytes);
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
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

  String _hash(String value) => sha1.convert(utf8.encode(value)).toString();

  String _extensionFor(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dotIndex = path.lastIndexOf('.');
    final ext = dotIndex == -1 ? '' : path.substring(dotIndex).toLowerCase();
    const allowed = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
    return allowed.contains(ext) ? ext : '.jpg';
  }
}
