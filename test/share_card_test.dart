import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:news_scrapper/features/news/data/datasources/share_data_source.dart';
import 'package:news_scrapper/features/news/data/models/article_model.dart';

const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

Future<Uint8List> _tinySamplePng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 40, 30));
  canvas.drawRect(const Rect.fromLTWH(0, 0, 40, 30), Paint()..color = const Color(0xFF336699));
  final image = await recorder.endRecording().toImage(40, 30);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void main() {
  testWidgets('composes a valid share card with and without a source image', (tester) async {
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

      final withImage = await ds.composeCardForTesting(article, await _tinySamplePng());
      final withoutImage = await ds.composeCardForTesting(article, null);

      expect(withImage.sublist(0, 8), _pngSignature);
      expect(withoutImage.sublist(0, 8), _pngSignature);
    });
  });
}
