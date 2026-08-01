import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for the OpenRouter API token.
class SecureTokenDataSource {
  static const _secureStorage = FlutterSecureStorage();
  static const _keyOpenRouterToken = 'openrouter_token';

  Future<String?> getOpenRouterToken() =>
      _secureStorage.read(key: _keyOpenRouterToken);

  Future<void> setOpenRouterToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _secureStorage.delete(key: _keyOpenRouterToken);
    } else {
      await _secureStorage.write(key: _keyOpenRouterToken, value: token);
    }
  }
}
