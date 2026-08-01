import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/news_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(const NewsScrapperApp());
}

class NewsScrapperApp extends StatelessWidget {
  const NewsScrapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => NewsProvider()),
      ],
      child: MaterialApp(
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
      ),
    );
  }
}
