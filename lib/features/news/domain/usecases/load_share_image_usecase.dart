import 'dart:ui' as ui;

import '../entities/article.dart';
import '../repositories/news_repository.dart';

class LoadShareImageUseCase {
  final NewsRepository _repository;

  LoadShareImageUseCase(this._repository);

  Future<ui.Image?> call(Article article) => _repository.loadShareImage(article);
}
