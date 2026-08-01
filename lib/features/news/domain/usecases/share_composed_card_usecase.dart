import 'dart:typed_data';

import '../entities/article.dart';
import '../repositories/news_repository.dart';

class ShareComposedCardUseCase {
  final NewsRepository _repository;

  ShareComposedCardUseCase(this._repository);

  Future<void> call(Article article, Uint8List pngBytes) =>
      _repository.shareComposedCard(article, pngBytes);
}
