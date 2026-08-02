import '../../../settings/domain/entities/news_source.dart';
import '../entities/cached_news.dart';
import '../repositories/news_repository.dart';

class GetCachedArticlesUseCase {
  final NewsRepository _repository;

  GetCachedArticlesUseCase(this._repository);

  Future<CachedNews> call({required List<NewsSource> sources}) =>
      _repository.getCachedNews(sources: sources);
}
