abstract interface class AccessTokenProvider {
  String? get accessToken;
}

abstract interface class AccessTokenRefresher {
  Future<String?> refreshAccessToken();
}
