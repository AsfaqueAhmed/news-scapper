import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../data/share/share_card_renderer.dart';
import '../entities/article.dart';
import '../repositories/news_repository.dart';

class ComposeShareCardUseCase {
  final NewsRepository _repository;

  ComposeShareCardUseCase(this._repository);

  Future<Uint8List> call(Article article, ui.Image? image, ShareCardConfig config) =>
      _repository.composeShareCard(article, image, config);
}
