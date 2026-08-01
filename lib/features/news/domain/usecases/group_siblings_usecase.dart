import '../entities/article.dart';

/// Pure lookup: returns every article (including [article] itself) that
/// shares its `groupId`, i.e. covers the same story across sources.
class GroupSiblingsUseCase {
  List<Article> call(List<Article> articles, Article article) {
    if (article.groupId == null) return [article];
    return articles.where((a) => a.groupId == article.groupId).toList();
  }
}
