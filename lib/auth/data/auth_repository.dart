import 'auth_api.dart';
import 'token_store.dart';

abstract interface class AuthRepository {
  Future<void> signIn({required String login, required String password});

  Future<String?> refreshAccessToken();

  String? get accessToken;

  Future<void> signOut();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({
    required AuthApi authApi,
    required DeviceIdentityProvider deviceIdentityProvider,
    required TokenStore tokenStore,
  })  : _authApi = authApi,
        _deviceIdentityProvider = deviceIdentityProvider,
        _tokenStore = tokenStore;

  final AuthApi _authApi;
  final DeviceIdentityProvider _deviceIdentityProvider;
  final TokenStore _tokenStore;
  String? _accessToken;

  @override
  String? get accessToken => _accessToken;

  @override
  Future<void> signIn({required String login, required String password}) async {
    final identity = await _deviceIdentityProvider.getOrCreate();
    final challenge =
        await _authApi.createChallenge(login: login, identity: identity);
    final authorization = await _authApi.verifyPassword(
      challengeId: challenge.id,
      password: password,
    );
    final tokens = await _authApi.exchangeAuthorizationCode(
      authorizationCode: authorization.value,
      deviceId: identity.deviceId,
    );
    await _tokenStore.writeRefreshToken(tokens.refreshToken);
    _accessToken = tokens.accessToken;
  }

  @override
  Future<String?> refreshAccessToken() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final identity = await _deviceIdentityProvider.getOrCreate();
      final tokens = await _authApi.refresh(
        refreshToken: refreshToken,
        deviceId: identity.deviceId,
      );
      await _tokenStore.writeRefreshToken(tokens.refreshToken);
      _accessToken = tokens.accessToken;
      return _accessToken;
    } catch (_) {
      _accessToken = null;
      await _tokenStore.clear();
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    _accessToken = null;
    await _tokenStore.clear();
    if (refreshToken == null || refreshToken.isEmpty) return;

    try {
      final identity = await _deviceIdentityProvider.getOrCreate();
      await _authApi.logout(
          refreshToken: refreshToken, deviceId: identity.deviceId);
    } catch (_) {
      // Local credential clearing takes precedence over a best-effort remote logout.
    }
  }
}

class DemoAuthRepository implements AuthRepository {
  const DemoAuthRepository({this.delay = const Duration(milliseconds: 450)});

  final Duration delay;

  @override
  String? get accessToken => null;

  @override
  Future<void> signIn({required String login, required String password}) async {
    await Future<void>.delayed(delay);
  }

  @override
  Future<String?> refreshAccessToken() async => null;

  @override
  Future<void> signOut() async {}
}
