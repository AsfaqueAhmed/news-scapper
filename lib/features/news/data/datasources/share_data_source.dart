import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/article_model.dart';

/// Wraps the native share sheet, attaching the article's image (downloaded
/// into a temp cache) alongside its title and link when one is available.
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

  Future<void> shareArticle(ArticleModel article) async {
    final text = '${article.title}\n${article.link}';
    final imagePath = await _cachedImagePath(article);

    await SharePlus.instance.share(
      imagePath != null
          ? ShareParams(text: text, files: [XFile(imagePath)])
          : ShareParams(text: text),
    );
  }

  /// Downloads the article's image into the temp cache (reusing it if
  /// already present) and prunes anything older than a day from that same
  /// cache. Returns null -- falling back to a text-only share -- if there's
  /// no image or the download fails.
  Future<String?> _cachedImagePath(ArticleModel article) async {
    final imageUrl = article.imageUrl;
    if (imageUrl == null) return null;

    final dir = await _cacheDir();
    await _pruneOldFiles(dir);

    final path = '${dir.path}/${article.id}${_extensionFor(imageUrl)}';
    final file = File(path);
    if (await file.exists()) return path;

    try {
      final response =
          await _client.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      await file.writeAsBytes(response.bodyBytes);
      return path;
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

  String _extensionFor(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dotIndex = path.lastIndexOf('.');
    final ext = dotIndex == -1 ? '' : path.substring(dotIndex).toLowerCase();
    const allowed = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};
    return allowed.contains(ext) ? ext : '.jpg';
  }
}
