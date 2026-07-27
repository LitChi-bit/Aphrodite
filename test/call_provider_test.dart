import 'package:aphrodite/chat/models/call.dart';
import 'package:aphrodite/chat/providers/call_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call controls update isolated call state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(callProvider.notifier);
    notifier.start(conversationId: 'conversation', kind: CallKind.audio);

    expect(container.read(callProvider).session?.status, CallStatus.active);
    expect(container.read(callProvider).cameraEnabled, isFalse);

    notifier.toggleMicrophone();
    expect(container.read(callProvider).microphoneEnabled, isFalse);

    notifier.end();
    expect(container.read(callProvider).session, isNull);
  });
}
