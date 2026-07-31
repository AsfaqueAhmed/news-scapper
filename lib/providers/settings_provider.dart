import 'package:flutter/foundation.dart';

import '../models/news_source.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';

class SettingsProvider extends ChangeNotifier {
  List<NewsSource> _sources = [];
  String? _openRouterToken;
  bool _loaded = false;

  List<NewsSource> get sources => List.unmodifiable(_sources);
  List<NewsSource> get enabledSources =>
      _sources.where((s) => s.enabled).toList();
  String? get openRouterToken => _openRouterToken;
  bool get hasOpenRouterToken =>
      _openRouterToken != null && _openRouterToken!.isNotEmpty;
  bool get loaded => _loaded;

  Future<void> load() async {
    _sources = await DatabaseService.instance.getSources();
    _openRouterToken = await SettingsService.instance.getOpenRouterToken();
    _loaded = true;
    notifyListeners();
  }

  Future<void> addSource(String name, String feedUrl) async {
    final id = '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().millisecondsSinceEpoch}';
    final source = NewsSource(id: id, name: name, feedUrl: feedUrl);
    await DatabaseService.instance.upsertSource(source);
    _sources = await DatabaseService.instance.getSources();
    notifyListeners();
  }

  Future<void> updateSource(NewsSource source) async {
    await DatabaseService.instance.upsertSource(source);
    _sources = await DatabaseService.instance.getSources();
    notifyListeners();
  }

  Future<void> toggleSource(NewsSource source, bool enabled) async {
    await updateSource(source.copyWith(enabled: enabled));
  }

  Future<void> removeSource(String id) async {
    await DatabaseService.instance.deleteSource(id);
    _sources = await DatabaseService.instance.getSources();
    notifyListeners();
  }

  Future<void> setOpenRouterToken(String? token) async {
    await SettingsService.instance.setOpenRouterToken(token);
    _openRouterToken = token;
    notifyListeners();
  }
}
