import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  SettingsService._internal();
  static final SettingsService instance = SettingsService._internal();

  static const _secureStorage = FlutterSecureStorage();
  static const _keyOpenRouterToken = 'openrouter_token';
  static const _keyLastScrapedAt = 'last_scraped_at';
  static const _keyLastSharedAt = 'last_shared_at';
  static const _keyLastSharedTitle = 'last_shared_title';
  static const _keyLastAutoShareAt = 'last_auto_share_at';
  static const _keyLastAutoShareTitle = 'last_auto_share_title';

  Future<String?> getOpenRouterToken() =>
      _secureStorage.read(key: _keyOpenRouterToken);

  Future<void> setOpenRouterToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _secureStorage.delete(key: _keyOpenRouterToken);
    } else {
      await _secureStorage.write(key: _keyOpenRouterToken, value: token);
    }
  }

  Future<DateTime?> getLastScrapedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyLastScrapedAt);
    return value != null ? DateTime.tryParse(value) : null;
  }

  Future<void> setLastScrapedAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastScrapedAt, time.toIso8601String());
  }

  Future<(DateTime, String)?> getLastShared() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyLastSharedAt);
    final title = prefs.getString(_keyLastSharedTitle);
    if (value == null || title == null) return null;
    final time = DateTime.tryParse(value);
    return time != null ? (time, title) : null;
  }

  Future<void> setLastShared(DateTime time, String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSharedAt, time.toIso8601String());
    await prefs.setString(_keyLastSharedTitle, title);
  }

  /// Manual share = the user tapped the native share sheet on an article.
  /// Auto share = the app posted an article to an external destination on
  /// its own (e.g. a configured channel). Auto-posting isn't wired up yet
  /// (needs a Facebook Page access token/app review), so this stays unset
  /// until that's implemented.
  Future<(DateTime, String)?> getLastAutoShared() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyLastAutoShareAt);
    final title = prefs.getString(_keyLastAutoShareTitle);
    if (value == null || title == null) return null;
    final time = DateTime.tryParse(value);
    return time != null ? (time, title) : null;
  }

  Future<void> setLastAutoShared(DateTime time, String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastAutoShareAt, time.toIso8601String());
    await prefs.setString(_keyLastAutoShareTitle, title);
  }
}
