enum AuthStatus { restoring, signedOut, authenticating, signedIn }

class AuthState {
  const AuthState({this.status = AuthStatus.restoring, this.errorMessage});

  final AuthStatus status;
  final String? errorMessage;
}
