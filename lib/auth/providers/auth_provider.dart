import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../models/auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => const DemoAuthRepository(),
);

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(repository: ref.watch(authRepositoryProvider)),
);

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({required this.repository}) : super(const AuthState());

  final AuthRepository repository;

  Future<bool> signIn({required String login, required String password}) async {
    if (login.trim().isEmpty || password.isEmpty) return false;
    state = const AuthState(status: AuthStatus.authenticating);
    try {
      await repository.signIn(login: login.trim(), password: password);
      state = const AuthState(status: AuthStatus.signedIn);
      return true;
    } catch (error) {
      state = AuthState(
        status: AuthStatus.signedOut,
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  Future<void> signOut() async {
    await repository.signOut();
    state = const AuthState();
  }
}
