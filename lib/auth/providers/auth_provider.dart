import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../models/auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => const DemoAuthRepository(),
);

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(repository: ref.watch(authRepositoryProvider));
  Future<void>.microtask(() async {
    if (!notifier.mounted) return;
    await notifier.restoreSession();
  });
  return notifier;
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({required this.repository}) : super(const AuthState());

  final AuthRepository repository;

  Future<void> restoreSession() async {
    try {
      final accessToken = await repository.refreshAccessToken();
      if (!mounted || state.status != AuthStatus.restoring) return;
      state = AuthState(
        status:
            accessToken == null ? AuthStatus.signedOut : AuthStatus.signedIn,
      );
    } catch (_) {
      if (mounted && state.status == AuthStatus.restoring) {
        state = const AuthState(status: AuthStatus.signedOut);
      }
    }
  }

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
    state = const AuthState(status: AuthStatus.signedOut);
  }
}
