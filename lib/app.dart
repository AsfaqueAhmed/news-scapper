import 'package:flutter/material.dart';

import 'features/news/presentation/screens/dashboard_screen.dart';

class NewsScrapperApp extends StatelessWidget {
  const NewsScrapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'News Scrapper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}
