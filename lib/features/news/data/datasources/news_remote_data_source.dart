import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_rss/dart_rss.dart';
import 'package:http/http.dart' as http;

import '../../../settings/domain/entities/news_source.dart';
import '../models/article_model.dart';

class RssFetchException implements Exception {
  final String sourceName;
  final String message;
  RssFetchException(this.sourceName, this.message);

  @override
  String toString() => 'RssFetchException($sourceName): $message';
}

class NewsRemoteDataSource {
  final http.Client _client;

  NewsRemoteDataSource(this._client);

  /// Fetches and parses a single source's feed. Throws [RssFetchException]
  /// on network or parse failure so callers can decide how to surface it
  /// without aborting the whole scrape run.
  Future<List<ArticleModel>> fetchSource(NewsSource source) async {
    late final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(source.feedUrl))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw RssFetchException(source.name, 'Network error: $e');
    }

    if (response.statusCode != 200) {
      throw RssFetchException(
        source.name,
        'HTTP ${response.statusCode}',
      );
    }

    final body = response.body;

    try {
      return _parseRss(body, source);
    } catch (_) {
      // Fall back to Atom if RSS parsing fails.
    }

    try {
      return _parseAtom(body, source);
    } catch (e) {
      throw RssFetchException(source.name, 'Could not parse feed: $e');
    }
  }

  List<ArticleModel> _parseRss(String body, NewsSource source) {
    final feed = RssFeed.parse(body);
    return feed.items.map((item) {
      final link = item.link ?? '';
      final title = item.title?.trim() ?? '(untitled)';
      final pubDate = _parseDate(item.pubDate) ?? DateTime.now();
      final imageUrl = item.enclosure?.url ??
          item.media?.contents.firstOrNull?.url ??
          item.media?.thumbnails.firstOrNull?.url ??
          _extractImageFromHtml(item.description);

      return ArticleModel(
        id: _articleId(source.id, link, title),
        title: title,
        link: link,
        description: _stripHtml(item.description),
        imageUrl: imageUrl,
        pubDate: pubDate,
        sourceId: source.id,
        sourceName: source.name,
      );
    }).where((a) => a.link.isNotEmpty).toList();
  }

  List<ArticleModel> _parseAtom(String body, NewsSource source) {
    final feed = AtomFeed.parse(body);
    return feed.items.map((item) {
      final link = item.links.firstOrNull?.href ?? '';
      final title = item.title?.trim() ?? '(untitled)';
      final pubDate =
          _parseDate(item.updated) ?? _parseDate(item.published) ?? DateTime.now();

      return ArticleModel(
        id: _articleId(source.id, link, title),
        title: title,
        link: link,
        description: _stripHtml(item.summary ?? item.content),
        imageUrl: null,
        pubDate: pubDate,
        sourceId: source.id,
        sourceName: source.name,
      );
    }).where((a) => a.link.isNotEmpty).toList();
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return _parseRfc822(raw);
    }
  }

  DateTime? _parseRfc822(String raw) {
    // Best-effort RFC 822 fallback (e.g. "Tue, 05 Aug 2025 10:00:00 GMT").
    try {
      final cleaned = raw.replaceAll(RegExp(r'\s+GMT$'), ' +0000');
      return DateTime.tryParse(cleaned);
    } catch (_) {
      return null;
    }
  }

  String? _stripHtml(String? html) {
    if (html == null) return null;
    final text = html.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    final decoded = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ');
    return decoded.isEmpty ? null : decoded;
  }

  String? _extractImageFromHtml(String? html) {
    if (html == null) return null;
    final match = RegExp(r'''<img[^>]+src=["']([^"']+)["']''').firstMatch(html);
    return match?.group(1);
  }

  String _articleId(String sourceId, String link, String title) {
    final basis = link.isNotEmpty ? link : '$sourceId|$title';
    return sha1.convert(utf8.encode(basis)).toString();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
