import 'package:aphrodite/auth/models/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores, replaces, and clears an in-memory access token', () {
    final session = InMemoryAuthSession();

    expect(session.accessToken, isNull);

    session.setAccessToken(' access-token-1 ');
    expect(session.accessToken, 'access-token-1');

    session.setAccessToken('access-token-2');
    expect(session.accessToken, 'access-token-2');

    session.clear();
    expect(session.accessToken, isNull);
  });

  test('rejects empty access tokens', () {
    final session = InMemoryAuthSession();

    expect(() => session.setAccessToken('  '), throwsArgumentError);
    expect(session.accessToken, isNull);
  });
}
