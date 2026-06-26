import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorage {
  static const _siteUrlKey = 'wmsm_site_url';
  static const _tokenKey = 'wmsm_token';
  static const _usernameKey = 'wmsm_username';
  static const _passwordKey = 'wmsm_password';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveSession({
    required String siteUrl,
    required String token,
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _siteUrlKey, value: siteUrl);
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<String?> getSiteUrl() => _storage.read(key: _siteUrlKey);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<String?> getUsername() => _storage.read(key: _usernameKey);

  Future<String?> getPassword() => _storage.read(key: _passwordKey);

  // خروج فقط اپ را قفل می‌کند و اطلاعات ذخیره‌شده را نگه می‌دارد.
  Future<void> lockSession() async {
    // عمداً چیزی از حافظه امن حذف نمی‌کنیم تا ورود سریع و اثر انگشت کار کند.
  }

  Future<void> clearAll() async {
    await _storage.delete(key: _siteUrlKey);
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
