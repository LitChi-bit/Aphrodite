import '../../../chat/data/dto/api_envelope.dart';

class AuthChallengeDto {
  const AuthChallengeDto({required this.id});

  final String id;

  factory AuthChallengeDto.fromResponse(Object? value) {
    final envelope = ApiEnvelope<Map<String, Object?>>.fromJson(
      requireJsonMap(value, 'auth challenge response'),
      (data) => requireJsonMap(data, 'auth challenge data'),
    );
    final id = envelope.data['challenge_id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('challenge_id must be a non-empty string');
    }
    return AuthChallengeDto(id: id);
  }
}

class AuthorizationCodeDto {
  const AuthorizationCodeDto({required this.value});

  final String value;

  factory AuthorizationCodeDto.fromResponse(Object? response) {
    final envelope = ApiEnvelope<Map<String, Object?>>.fromJson(
      requireJsonMap(response, 'authorization response'),
      (data) => requireJsonMap(data, 'authorization data'),
    );
    final authorizationCode = envelope.data['authorization_code'];
    if (authorizationCode is! String || authorizationCode.isEmpty) {
      throw const FormatException(
          'authorization_code must be a non-empty string');
    }
    return AuthorizationCodeDto(value: authorizationCode);
  }
}

class TokenPairDto {
  const TokenPairDto({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory TokenPairDto.fromResponse(Object? value) {
    final envelope = ApiEnvelope<Map<String, Object?>>.fromJson(
      requireJsonMap(value, 'token response'),
      (data) => requireJsonMap(data, 'token data'),
    );
    final accessToken = envelope.data['access_token'];
    final refreshToken = envelope.data['refresh_token'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      throw const FormatException(
          'token response must contain non-empty tokens');
    }
    return TokenPairDto(accessToken: accessToken, refreshToken: refreshToken);
  }
}
