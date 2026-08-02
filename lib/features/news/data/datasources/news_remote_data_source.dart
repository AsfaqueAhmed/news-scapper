import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_rss/dart_rss.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/supabase_config.dart';
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
  ///
  /// Routed through the `fetch-feed` Supabase Edge Function rather than
  /// fetched directly: most news RSS feeds don't send CORS headers, so a
  /// direct browser fetch is blocked on web. The edge function fetches the
  /// feed server-side and returns it with permissive CORS headers, and
  /// works the same way on every platform.
  Future<List<ArticleModel>> fetchSource(NewsSource source) async {
    final proxyUrl = Uri.parse('${SupabaseConfig.url}/functions/v1/fetch-feed')
        .replace(queryParameters: {'url': source.feedUrl});

    late final http.Response response;
    try {
      response = await _client.get(proxyUrl).timeout(const Duration(seconds: 20));
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

  static final _rfc822Pattern = RegExp(
    r'^(?:[A-Za-z]{3,},\s*)?(\d{1,2})\s+([A-Za-z]{3,})\s+(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s*(.*)$',
  );

  static const _monthAbbreviations = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const _timezoneAbbreviationOffsets = {
    'GMT': 0, 'UTC': 0, 'UT': 0,
    'EST': -300, 'EDT': -240,
    'CST': -360, 'CDT': -300,
    'MST': -420, 'MDT': -360,
    'PST': -480, 'PDT': -420,
  };

  /// [DateTime.parse] only understands ISO 8601, but RSS `pubDate`/Atom
  /// `updated` fields are almost always RFC 822/1123 (e.g. "Tue, 05 Aug
  /// 2025 10:00:00 GMT" or "+0600"), which Dart's core parser rejects
  /// outright -- so this fell back to [DateTime.now] for nearly every real
  /// feed, silently corrupting publish dates on every refresh. Parsed by
  /// hand instead of relying on [DateTime.parse]/[DateTime.tryParse] again.
  DateTime? _parseRfc822(String raw) {
    final match = _rfc822Pattern.firstMatch(raw.trim());
    if (match == null) return null;

    final day = int.tryParse(match.group(1)!);
    final month = _monthAbbreviations[match.group(2)!.substring(0, 3).toLowerCase()];
    final year = int.tryParse(match.group(3)!);
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final second = int.tryParse(match.group(6)!);
    if (day == null || month == null || year == null || hour == null || minute == null || second == null) {
      return null;
    }

    final offsetMinutes = _parseTimezoneOffset(match.group(7)!.trim());
    return DateTime.utc(year, month, day, hour, minute, second).subtract(Duration(minutes: offsetMinutes));
  }

  int _parseTimezoneOffset(String zone) {
    if (zone.isEmpty) return 0;
    final numeric = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(zone);
    if (numeric != null) {
      final sign = numeric.group(1) == '-' ? -1 : 1;
      final hours = int.parse(numeric.group(2)!);
      final minutes = int.parse(numeric.group(3)!);
      return sign * (hours * 60 + minutes);
    }
    return _timezoneAbbreviationOffsets[zone.toUpperCase()] ?? 0;
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

  // Scoped by source: a publisher that runs multiple feeds (e.g. BBC's
  // News/UK/World feeds all link back to the same bbc.co.uk article URLs)
  // would otherwise collapse into a single row, with whichever source's
  // batch ran last silently overwriting the others. Keeping them as
  // separate per-source rows matches how genuinely different publishers
  // covering the same story already work -- the AI enrichment's groupId
  // links them together as "N sources" instead of one silently winning.
  String _articleId(String sourceId, String link, String title) {
    final basis = link.isNotEmpty ? '$sourceId|$link' : '$sourceId|$title';
    return sha1.convert(utf8.encode(basis)).toString();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
