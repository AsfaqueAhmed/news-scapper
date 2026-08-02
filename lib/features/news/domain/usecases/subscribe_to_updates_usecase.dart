import '../repositories/news_repository.dart';

class SubscribeToUpdatesUseCase {
  final NewsRepository _repository;

  SubscribeToUpdatesUseCase(this._repository);

  void call(void Function() onChanged) => _repository.subscribeToUpdates(onChanged);
}
