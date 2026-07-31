import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:news_scrapper/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Dashboard renders with app bar', (WidgetTester tester) async {
    await tester.pumpWidget(const NewsScrapperApp());
    await tester.pump();

    expect(find.text('News Dashboard'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
