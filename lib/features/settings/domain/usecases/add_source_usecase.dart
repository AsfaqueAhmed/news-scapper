import '../entities/news_source.dart';
import '../repositories/settings_repository.dart';

/// Builds a [NewsSource] with a name-derived id and persists it.
class AddSourceUseCase {
  final SettingsRepository _repository;

  AddSourceUseCase(this._repository);

  Future<void> call(String name, String feedUrl) async {
    final id =
        '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().millisecondsSinceEpoch}';
    final source = NewsSource(id: id, name: name, feedUrl: feedUrl);
    await _repository.upsertSource(source);
  }
}
