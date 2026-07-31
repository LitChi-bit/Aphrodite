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
  Future<void> _operationTail = Future<void>.value();
  int _pendingOperations = 0;

  Future<T> _runExclusively<T>(Future<T> Function() operation) {
    final startImmediately = _pendingOperations == 0;
    _pendingOperations += 1;
    final future = startImmediately
        ? Future<T>.sync(operation)
        : _operationTail.then((_) => Future<T>.sync(operation));
    _operationTail = future.then<void>(
      (result) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return future.whenComplete(() => _pendingOperations -= 1);
  }

  Future<void> restoreSession() => _runExclusively(_restoreSession);

  Future<void> _restoreSession() async {
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

  Future<bool> signIn({required String login, required String password}) {
    if (login.trim().isEmpty || password.isEmpty) return Future.value(false);
    return _runExclusively(
      () => _signIn(login: login.trim(), password: password),
    );
  }

  Future<bool> _signIn(
      {required String login, required String password}) async {
    state = const AuthState(status: AuthStatus.authenticating);
    try {
      await repository.signIn(login: login, password: password);
      if (mounted) state = const AuthState(status: AuthStatus.signedIn);
      return true;
    } catch (error) {
      if (mounted) {
        state = AuthState(
          status: AuthStatus.signedOut,
          errorMessage: error.toString(),
        );
      }
      return false;
    }
  }

  Future<void> signOut() => _runExclusively(_signOut);

  Future<void> _signOut() async {
    await repository.signOut();
    if (mounted) state = const AuthState(status: AuthStatus.signedOut);
  }
}
