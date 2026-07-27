import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/call_controller.dart';
import '../models/call.dart';

final callProvider = StateNotifierProvider<CallNotifier, CallViewState>(
  (ref) => CallNotifier(),
);

class CallNotifier extends StateNotifier<CallViewState> {
  CallNotifier() : super(const CallViewState());

  void start({required String conversationId, required CallKind kind}) {
    final now = DateTime.now();
    state = CallViewState(
      session: CallSession(
        id: 'call-${now.microsecondsSinceEpoch}',
        conversationId: conversationId,
        initiatorId: 'self',
        participantIds: const ['self', 'other'],
        kind: kind,
        status: CallStatus.active,
        startedAt: now,
        connectedAt: now,
      ),
      cameraEnabled: kind == CallKind.video,
    );
  }

  void toggleMicrophone() => state = state.copyWith(
        microphoneEnabled: !state.microphoneEnabled,
      );

  void toggleCamera() => state = state.copyWith(
        cameraEnabled: !state.cameraEnabled,
      );

  void toggleSpeaker() => state = state.copyWith(
        speakerEnabled: !state.speakerEnabled,
      );

  void end() => state = const CallViewState();
}
