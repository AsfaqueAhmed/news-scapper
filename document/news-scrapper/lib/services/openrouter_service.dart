import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/article.dart';

class OpenRouterException implements Exception {
  final String message;
  OpenRouterException(this.message);

  @override
  String toString() => 'OpenRouterException: $message';
}

class ArticleEnrichment {
  final String articleId;
  final String? category;
  final String? groupId;

  ArticleEnrichment({required this.articleId, this.category, this.groupId});
}

/// Uses an OpenRouter-hosted LLM to tag articles with a topic category and
/// to detect when articles from different sources cover the same story,
/// assigning them a shared groupId.
class OpenRouterService {
  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const _defaultModel = 'openai/gpt-4o-mini';

  final http.Client _client;

  OpenRouterService({http.Client? client}) : _client = client ?? http.Client();

  /// [runId] scopes the group keys the model returns (which are only
  /// unique within this single batch) so articles from different scrape
  /// runs never collide into the same stored groupId.
  Future<List<ArticleEnrichment>> enrich(
    List<Article> articles,
    String apiToken, {
    required String runId,
    String model = _defaultModel,
  }) async {
    if (articles.isEmpty) return [];

    final indexed = [
      for (var i = 0; i < articles.length; i++)
        {
          'index': i,
          'title': articles[i].title,
          'source': articles[i].sourceName,
          'description': articles[i].description ?? '',
        }
    ];

    final prompt = '''
You are given a JSON array of news articles freshly scraped from multiple
RSS sources. For each article, decide:
1. "category": a short topic label (e.g. "Politics", "Technology", "Sports",
   "Business", "Health", "Science", "Entertainment", "World", "Other").
2. "group": an integer group key shared by every article that reports on
   the SAME real-world news story, even if wording differs across sources.
   Articles that are the only coverage of their story get a group key that
   no other article shares (e.g. their own index).

Articles:
${jsonEncode(indexed)}

Respond with ONLY a JSON array, no prose, in this exact shape:
[{"index": 0, "category": "Technology", "group": 0}, ...]
''';

    final response = await _client
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Authorization': 'Bearer $apiToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'temperature': 0,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw OpenRouterException('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        decoded['choices']?[0]?['message']?['content'] as String?;
    if (content == null) {
      throw OpenRouterException('Unexpected response shape: ${response.body}');
    }

    final jsonText = _extractJsonArray(content);
    final List<dynamic> parsed;
    try {
      parsed = jsonDecode(jsonText) as List<dynamic>;
    } catch (e) {
      throw OpenRouterException('Could not parse model output as JSON: $e');
    }

    final results = <ArticleEnrichment>[];
    for (final entry in parsed) {
      final map = entry as Map<String, dynamic>;
      final index = map['index'] as int?;
      if (index == null || index < 0 || index >= articles.length) continue;
      final groupKey = map['group'];
      results.add(
        ArticleEnrichment(
          articleId: articles[index].id,
          category: map['category'] as String?,
          groupId: groupKey != null ? '${runId}_g${groupKey.toString()}' : null,
        ),
      );
    }
    return results;
  }

  String _extractJsonArray(String content) {
    final start = content.indexOf('[');
    final end = content.lastIndexOf(']');
    if (start == -1 || end == -1 || end < start) {
      throw OpenRouterException('No JSON array found in model output');
    }
    return content.substring(start, end + 1);
  }
}
