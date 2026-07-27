import '../models/call.dart';

const Object _unset = Object();

class CallViewState {
  const CallViewState({
    this.session,
    this.microphoneEnabled = true,
    this.cameraEnabled = true,
    this.speakerEnabled = true,
    this.isReconnecting = false,
  });

  final CallSession? session;
  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool speakerEnabled;
  final bool isReconnecting;

  CallViewState copyWith({
    Object? session = _unset,
    bool? microphoneEnabled,
    bool? cameraEnabled,
    bool? speakerEnabled,
    bool? isReconnecting,
  }) {
    return CallViewState(
      session:
          identical(session, _unset) ? this.session : session as CallSession?,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      speakerEnabled: speakerEnabled ?? this.speakerEnabled,
      isReconnecting: isReconnecting ?? this.isReconnecting,
    );
  }
}
