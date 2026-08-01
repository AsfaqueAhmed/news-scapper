import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:news_scrapper/features/news/data/datasources/share_data_source.dart';
import 'package:news_scrapper/features/news/data/models/article_model.dart';
import 'package:news_scrapper/features/news/data/share/share_card_renderer.dart';

const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

Future<ui.Image> _tinySampleImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 40, 30));
  canvas.drawRect(const Rect.fromLTWH(0, 0, 40, 30), Paint()..color = const Color(0xFF336699));
  return recorder.endRecording().toImage(40, 30);
}

void main() {
  testWidgets('composes a valid share card for every template, with and without an image',
      (tester) async {
    await tester.runAsync(() async {
      final ds = ShareDataSource(http.Client());
      final article = ArticleModel(
        id: 'a',
        title: 'Flood warnings issued as heavy rain batters Dhaka and surrounding districts',
        link: 'https://example.com/a',
        pubDate: DateTime.now(),
        sourceId: 'bbc',
        sourceName: 'BBC News',
      );
      final image = await _tinySampleImage();

      for (final template in shareTemplates) {
        final config = ShareCardConfig(
          titlePosition: template.titlePosition,
          showTitle: template.showTitle,
          zoom: 1.5,
          pan: const Offset(0.3, -0.2),
        );

        final withImage = await ds.composeCard(article, image, config);
        final withoutImage = await ds.composeCard(article, null, config);

        expect(withImage.sublist(0, 8), _pngSignature, reason: '${template.id} with image');
        expect(withoutImage.sublist(0, 8), _pngSignature, reason: '${template.id} without image');
      }
    });
  });
}
