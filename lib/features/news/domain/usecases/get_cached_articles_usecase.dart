import '../entities/cached_news.dart';
import '../repositories/news_repository.dart';

class GetCachedArticlesUseCase {
  final NewsRepository _repository;

  GetCachedArticlesUseCase(this._repository);

  Future<CachedNews> call() => _repository.getCachedNews();
}
