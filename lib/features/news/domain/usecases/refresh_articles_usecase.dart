import '../../../settings/domain/entities/news_source.dart';
import '../entities/refresh_result.dart';
import '../repositories/news_repository.dart';

class RefreshArticlesUseCase {
  final NewsRepository _repository;

  RefreshArticlesUseCase(this._repository);

  Future<RefreshResult> call({
    required List<NewsSource> sources,
    String? openRouterToken,
  }) =>
      _repository.refresh(sources: sources, openRouterToken: openRouterToken);
}
