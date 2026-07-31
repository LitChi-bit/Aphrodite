import 'dart:async';

import 'package:aphrodite/auth/data/auth_repository.dart';
import 'package:aphrodite/auth/models/auth_state.dart';
import 'package:aphrodite/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores a signed-in state when a refresh token produces access token',
      () async {
    final repository = _FakeAuthRepository()
      ..restoredAccessToken = 'access-token';
    final notifier = AuthNotifier(repository: repository);
    addTearDown(notifier.dispose);

    expect(notifier.state.status, AuthStatus.restoring);
    await notifier.restoreSession();

    expect(notifier.state.status, AuthStatus.signedIn);
  });

  test('restore returns to signed out without an available refresh token',
      () async {
    final notifier = AuthNotifier(repository: _FakeAuthRepository());
    addTearDown(notifier.dispose);

    await notifier.restoreSession();

    expect(notifier.state.status, AuthStatus.signedOut);
  });

  test('restore failure returns to signed out without exposing an error',
      () async {
    final notifier = AuthNotifier(
      repository: _FakeAuthRepository()..refreshError = StateError('failed'),
    );
    addTearDown(notifier.dispose);

    await notifier.restoreSession();

    expect(notifier.state.status, AuthStatus.signedOut);
    expect(notifier.state.errorMessage, isNull);
  });

  test('empty credentials are rejected without calling repository', () async {
    final repository = _FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(authProvider.notifier)
        .signIn(login: ' ', password: '');

    expect(result, isFalse);
    expect(repository.signInCalls, 0);
    expect(container.read(authProvider).status, AuthStatus.restoring);
  });

  test('successful sign in transitions through authenticating', () async {
    final repository = _FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final signIn = container.read(authProvider.notifier).signIn(
          login: ' example-user ',
          password: 'example-password',
        );

    expect(container.read(authProvider).status, AuthStatus.authenticating);
    expect(repository.receivedLogin, 'example-user');

    repository.completeSignIn();
    expect(await signIn, isTrue);
    expect(container.read(authProvider).status, AuthStatus.signedIn);
    expect(container.read(authProvider).errorMessage, isNull);
  });

  test('repository failure returns to signed out with an error', () async {
    final repository = _FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final signIn = container.read(authProvider.notifier).signIn(
          login: 'example-user',
          password: 'example-password',
        );
    repository.failSignIn(const _ControlledAuthFailure());

    expect(await signIn, isFalse);
    final state = container.read(authProvider);
    expect(state.status, AuthStatus.signedOut);
    expect(state.errorMessage, contains('controlled authentication failure'));
  });

  test('sign out delegates to repository and clears state', () async {
    final repository = _FakeAuthRepository();
    final notifier = AuthNotifier(repository: repository);
    addTearDown(notifier.dispose);

    final signIn = notifier.signIn(
      login: 'example-user',
      password: 'example-password',
    );
    repository.completeSignIn();
    await signIn;

    await notifier.signOut();

    expect(repository.signOutCalls, 1);
    expect(notifier.state.status, AuthStatus.signedOut);
    expect(notifier.state.errorMessage, isNull);
  });
}

class _FakeAuthRepository implements AuthRepository {
  final Completer<void> _signInCompleter = Completer<void>();
  int signInCalls = 0;
  int signOutCalls = 0;
  String? receivedLogin;
  String? restoredAccessToken;
  Object? refreshError;

  @override
  String? get accessToken => null;

  @override
  Future<String?> refreshAccessToken() async {
    if (refreshError != null) throw refreshError!;
    return restoredAccessToken;
  }

  @override
  Future<void> signIn({required String login, required String password}) {
    signInCalls += 1;
    receivedLogin = login;
    return _signInCompleter.future;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }

  void completeSignIn() => _signInCompleter.complete();

  void failSignIn(Object error) => _signInCompleter.completeError(error);
}

class _ControlledAuthFailure implements Exception {
  const _ControlledAuthFailure();

  @override
  String toString() => 'controlled authentication failure';
}
