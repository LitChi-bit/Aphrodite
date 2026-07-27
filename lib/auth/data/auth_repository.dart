abstract interface class AuthRepository {
  Future<void> signIn({required String login, required String password});

  Future<void> signOut();
}

class DemoAuthRepository implements AuthRepository {
  const DemoAuthRepository({this.delay = const Duration(milliseconds: 450)});

  final Duration delay;

  @override
  Future<void> signIn({required String login, required String password}) async {
    await Future<void>.delayed(delay);
  }

  @override
  Future<void> signOut() async {}
}
