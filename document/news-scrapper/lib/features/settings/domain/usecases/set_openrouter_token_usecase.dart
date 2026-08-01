import '../repositories/settings_repository.dart';

class SetOpenRouterTokenUseCase {
  final SettingsRepository _repository;

  SetOpenRouterTokenUseCase(this._repository);

  Future<void> call(String? token) => _repository.setOpenRouterToken(token);
}
