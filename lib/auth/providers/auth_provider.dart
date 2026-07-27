import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_state.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  Future<bool> signIn({required String login, required String password}) async {
    if (login.trim().isEmpty || password.isEmpty) return false;
    state = const AuthState(status: AuthStatus.authenticating);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    state = const AuthState(status: AuthStatus.signedIn);
    return true;
  }

  void signOut() => state = const AuthState();
}
