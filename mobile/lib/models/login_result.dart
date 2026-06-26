class LoginResult {
  LoginResult({
    required this.token,
    required this.siteUrl,
    required this.displayName,
  });

  final String token;
  final String siteUrl;
  final String displayName;

  factory LoginResult.fromJson(Map<String, dynamic> json, String siteUrl) {
    return LoginResult(
      token: (json['token'] ?? '').toString(),
      siteUrl: siteUrl,
      displayName: (json['user']?['display_name'] ?? 'کاربر').toString(),
    );
  }
}
