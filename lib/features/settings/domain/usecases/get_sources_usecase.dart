import '../entities/news_source.dart';
import '../repositories/settings_repository.dart';

class GetSourcesUseCase {
  final SettingsRepository _repository;

  GetSourcesUseCase(this._repository);

  Future<List<NewsSource>> call() => _repository.getSources();
}
