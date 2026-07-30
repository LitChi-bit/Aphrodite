import '../../core/storage/secure_store.dart';

class TokenStore {
  const TokenStore({required SecureStore secureStore})
      : _secureStore = secureStore;

  static const _refreshTokenKey = 'auth.refresh_token';

  final SecureStore _secureStore;

  Future<String?> readRefreshToken() => _secureStore.read(_refreshTokenKey);

  Future<void> writeRefreshToken(String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
    return _secureStore.write(_refreshTokenKey, value);
  }

  Future<void> clear() => _secureStore.delete(_refreshTokenKey);
}
