import '../repositories/settings_repository.dart';

class RemoveSourceUseCase {
  final SettingsRepository _repository;

  RemoveSourceUseCase(this._repository);

  Future<void> call(String id) => _repository.deleteSource(id);
}
