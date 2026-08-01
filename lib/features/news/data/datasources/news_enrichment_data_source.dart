import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/article_model.dart';

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

/// Calls the `enrich-articles` Supabase Edge Function, which asks an
/// OpenRouter-hosted LLM to tag articles with a topic category and detect
/// when articles from different sources cover the same story, assigning
/// them a shared groupId. The OpenRouter key lives server-side (as the
/// edge function's `OPENROUTER_API_KEY` secret) so it never ships in the
/// client; [apiToken] is only sent when the user has set their own.
class NewsEnrichmentDataSource {
  final SupabaseClient _client;

  NewsEnrichmentDataSource(this._client);

  /// [runId] scopes the group keys the model returns (which are only
  /// unique within this single batch) so articles from different scrape
  /// runs never collide into the same stored groupId.
  Future<List<ArticleEnrichment>> enrich(
    List<ArticleModel> articles, {
    required String runId,
    String? apiToken,
  }) async {
    if (articles.isEmpty) return [];

    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'enrich-articles',
        body: {
          'runId': runId,
          if (apiToken != null && apiToken.isNotEmpty) 'userToken': apiToken,
          'articles': [
            for (final a in articles)
              {
                'id': a.id,
                'title': a.title,
                'source': a.sourceName,
                'description': a.description ?? '',
              },
          ],
        },
      );
    } on FunctionException catch (e) {
      throw OpenRouterException('HTTP ${e.status}: ${e.details}');
    } catch (e) {
      throw OpenRouterException('Request failed: $e');
    }

    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw OpenRouterException(data['error'].toString());
    }
    if (data is! List) {
      throw OpenRouterException('Unexpected response shape: $data');
    }

    return [
      for (final entry in data)
        ArticleEnrichment(
          articleId: entry['articleId'] as String,
          category: entry['category'] as String?,
          groupId: entry['groupId'] as String?,
        ),
    ];
  }
}
