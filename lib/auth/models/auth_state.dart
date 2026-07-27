enum AuthStatus { signedOut, authenticating, signedIn }

class AuthState {
  const AuthState({this.status = AuthStatus.signedOut, this.errorMessage});

  final AuthStatus status;
  final String? errorMessage;
}
