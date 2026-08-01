import '../repositories/settings_repository.dart';

class GetOpenRouterTokenUseCase {
  final SettingsRepository _repository;

  GetOpenRouterTokenUseCase(this._repository);

  Future<String?> call() => _repository.getOpenRouterToken();
}
