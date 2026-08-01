import '../repositories/news_repository.dart';

class MarkArticleReadUseCase {
  final NewsRepository _repository;

  MarkArticleReadUseCase(this._repository);

  Future<void> call(String articleId) => _repository.markRead(articleId);
}
