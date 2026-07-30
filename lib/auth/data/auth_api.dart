import '../../core/network/network_client.dart';
import 'dto/auth_dto.dart';

class AuthApi {
  const AuthApi({required NetworkClient networkClient})
      : _networkClient = networkClient;

  final NetworkClient _networkClient;

  Future<AuthChallengeDto> createChallenge({
    required String login,
    required DeviceIdentity identity,
  }) async {
    final response = await _networkClient.post(
      '/v1/auth/challenges',
      data: {
        'login': login,
        'device_id': identity.deviceId,
        'device_name': identity.deviceName,
        'platform': identity.platform,
        'identity_public_key': identity.identityPublicKeyBase64,
      },
    );
    return AuthChallengeDto.fromResponse(response);
  }

  Future<AuthorizationCodeDto> verifyPassword({
    required String challengeId,
    required String password,
  }) async {
    final response = await _networkClient.post(
      '/v1/auth/challenges/$challengeId/verify',
      data: {'factor': 'password', 'step': 'primary', 'value': password},
    );
    return AuthorizationCodeDto.fromResponse(response);
  }

  Future<TokenPairDto> exchangeAuthorizationCode({
    required String authorizationCode,
    required String deviceId,
  }) async {
    final response = await _networkClient.post(
      '/v1/auth/token',
      data: {
        'grant_type': 'authorization_code',
        'code': authorizationCode,
        'device_id': deviceId,
      },
    );
    return TokenPairDto.fromResponse(response);
  }

  Future<TokenPairDto> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    final response = await _networkClient.post(
      '/v1/auth/token',
      data: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'device_id': deviceId,
      },
    );
    return TokenPairDto.fromResponse(response);
  }

  Future<void> logout({
    required String refreshToken,
    required String deviceId,
  }) async {
    await _networkClient.post(
      '/v1/auth/logout',
      data: {'refresh_token': refreshToken, 'device_id': deviceId},
    );
  }
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.identityPublicKeyBase64,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String identityPublicKeyBase64;
}

abstract interface class DeviceIdentityProvider {
  Future<DeviceIdentity> getOrCreate();
}
