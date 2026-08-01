import '../entities/news_source.dart';
import '../repositories/settings_repository.dart';

class UpdateSourceUseCase {
  final SettingsRepository _repository;

  UpdateSourceUseCase(this._repository);

  Future<void> call(NewsSource source) => _repository.upsertSource(source);
}
