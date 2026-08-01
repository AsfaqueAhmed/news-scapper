import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/news/presentation/screens/dashboard_screen.dart';

class NewsScrapperApp extends StatelessWidget {
  const NewsScrapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'News Scrapper',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const DashboardScreen(),
    );
  }
}
