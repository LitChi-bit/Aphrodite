import '../../core/network/access_token_provider.dart';

abstract interface class AuthSession implements AccessTokenProvider {
  AccessTokenRefresher? get refresher;

  void setAccessToken(String value);

  void setRefresher(AccessTokenRefresher refresher);

  void clear();
}

final class InMemoryAuthSession implements AuthSession {
  String? _accessToken;
  AccessTokenRefresher? _refresher;

  @override
  String? get accessToken => _accessToken;

  @override
  AccessTokenRefresher? get refresher => _refresher;

  @override
  void clear() {
    _accessToken = null;
  }

  @override
  void setRefresher(AccessTokenRefresher refresher) {
    _refresher = refresher;
  }

  @override
  void setAccessToken(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
          value, 'value', 'Access token must not be empty.');
    }
    _accessToken = normalized;
  }
}
