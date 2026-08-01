import '../entities/article.dart';
import '../repositories/news_repository.dart';

class ShareArticleUseCase {
  final NewsRepository _repository;

  ShareArticleUseCase(this._repository);

  Future<void> call(Article article) => _repository.shareArticle(article);
}
