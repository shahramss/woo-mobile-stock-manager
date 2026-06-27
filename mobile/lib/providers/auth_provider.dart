import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../services/api_service.dart';
import '../services/auth_storage.dart';

class AuthProvider extends ChangeNotifier {
  final AuthStorage _storage = AuthStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  String? _siteUrl;
  String? _token;
  String? _savedSiteUrl;
  String? _savedUsername;
  String? _savedPassword;
  String? _savedToken;
  bool _isBusy = false;

  bool get isLoggedIn => _siteUrl != null && _token != null;
  bool get isBusy => _isBusy;
  String? get siteUrl => _siteUrl;
  String? get savedSiteUrl => _savedSiteUrl;
  String? get savedUsername => _savedUsername;
  String? get savedPassword => _savedPassword;
  bool get hasSavedLogin {
    return (_savedSiteUrl?.isNotEmpty ?? false) &&
        ((_savedToken?.isNotEmpty ?? false) ||
            ((_savedUsername?.isNotEmpty ?? false) && (_savedPassword?.isNotEmpty ?? false)));
  }

  ApiService get api {
    if (_siteUrl == null || _token == null) {
      throw ApiException('ابتدا وارد حساب شوید.');
    }
    return ApiService(siteUrl: _siteUrl!, token: _token);
  }

  Future<void> loadSavedSession() async {
    _savedSiteUrl = await _storage.getSiteUrl();
    _savedUsername = await _storage.getUsername();
    _savedPassword = await _storage.getPassword();
    _savedToken = await _storage.getToken();

    // برای امنیت، بعد از باز شدن اپ مستقیم وارد نمی‌شویم.
    // کاربر می‌تواند با اثر انگشت یا دکمه ورود وارد شود.
    _siteUrl = null;
    _token = null;
    notifyListeners();
  }

  Future<void> login({
    required String siteUrl,
    required String username,
    required String password,
  }) async {
    _setBusy(true);
    try {
      final api = ApiService(siteUrl: siteUrl);
      final result = await api.login(username: username, password: password);
      _siteUrl = result.siteUrl;
      _token = result.token;
      _savedSiteUrl = result.siteUrl;
      _savedUsername = username.trim();
      _savedPassword = password;
      _savedToken = result.token;
      await _storage.saveSession(
        siteUrl: result.siteUrl,
        token: result.token,
        username: username.trim(),
        password: password,
      );
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> loginWithBiometric() async {
    if (!hasSavedLogin) {
      throw ApiException('اطلاعات ورود ذخیره‌شده پیدا نشد. یک‌بار با نام کاربری و رمز وارد شوید.');
    }

    _setBusy(true);
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported && !canCheck) {
        throw ApiException('اثر انگشت یا قفل امن روی این گوشی فعال نیست.');
      }

      final ok = await _localAuth.authenticate(
        localizedReason: 'برای ورود به مدیریت سریع هویت خود را تأیید کنید',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (!ok) {
        throw ApiException('ورود با اثر انگشت لغو شد.');
      }

      // بعد از تأیید اثر انگشت، با نام کاربری و رمز ذخیره‌شده دوباره لاگین می‌کنیم
      // تا اگر توکن قبلی منقضی شده بود، توکن جدید دریافت شود.
      if ((_savedSiteUrl?.isNotEmpty ?? false) &&
          (_savedUsername?.isNotEmpty ?? false) &&
          (_savedPassword?.isNotEmpty ?? false)) {
        final api = ApiService(siteUrl: _savedSiteUrl!);
        final result = await api.login(username: _savedUsername!, password: _savedPassword!);
        _siteUrl = result.siteUrl;
        _token = result.token;
        _savedToken = result.token;
        await _storage.saveSession(
          siteUrl: result.siteUrl,
          token: result.token,
          username: _savedUsername!,
          password: _savedPassword!,
        );
        notifyListeners();
        return;
      }

      if ((_savedSiteUrl?.isNotEmpty ?? false) && (_savedToken?.isNotEmpty ?? false)) {
        _siteUrl = _savedSiteUrl;
        _token = _savedToken;
        notifyListeners();
        return;
      }

      throw ApiException('اطلاعات ذخیره‌شده کامل نیست. دوباره وارد شوید.');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    await _storage.lockSession();
    _siteUrl = null;
    _token = null;
    notifyListeners();
  }

  Future<void> clearSavedLogin() async {
    await _storage.clearAll();
    _siteUrl = null;
    _token = null;
    _savedSiteUrl = null;
    _savedUsername = null;
    _savedPassword = null;
    _savedToken = null;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }
}
