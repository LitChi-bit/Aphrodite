import 'package:aphrodite/chat/application/call_controller.dart';
import 'package:aphrodite/chat/models/call.dart';
import 'package:aphrodite/chat/models/conversation.dart';
import 'package:aphrodite/chat/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nullable copyWith fields', () {
    test('conversation preserves omitted values and clears explicit nulls', () {
      final now = DateTime(2026, 7, 26);
      final conversation = Conversation(
        id: 'conversation',
        kind: ConversationKind.direct,
        title: 'Title',
        participantIds: const ['self', 'other'],
        subtitle: 'Subtitle',
        lastMessagePreview: 'Preview',
        lastMessageAt: now,
        createdAt: now,
        updatedAt: now,
      );

      expect(conversation.copyWith().subtitle, 'Subtitle');
      expect(conversation.copyWith(subtitle: null).subtitle, isNull);
      expect(
        conversation.copyWith(lastMessagePreview: null).lastMessagePreview,
        isNull,
      );
      expect(conversation.copyWith(lastMessageAt: null).lastMessageAt, isNull);
    });

    test('message preserves omitted failure and clears explicit null', () {
      final message = ChatMessage(
        id: 'message',
        conversationId: 'conversation',
        senderId: 'self',
        clientMessageId: 'client-message',
        kind: ChatMessageKind.text,
        status: ChatMessageStatus.failed,
        encryptionState: MessageEncryptionState.plain,
        text: 'Hello',
        failureReason: 'Network error',
        createdAt: DateTime(2026, 7, 26),
      );

      expect(message.copyWith().failureReason, 'Network error');
      expect(message.copyWith(failureReason: null).failureReason, isNull);
      expect(message.copyWith(text: null).text, isNull);
    });

    test('call state supports clearing a session explicitly', () {
      final now = DateTime(2026, 7, 26);
      final session = CallSession(
        id: 'call',
        conversationId: 'conversation',
        initiatorId: 'self',
        participantIds: const ['self', 'other'],
        kind: CallKind.audio,
        status: CallStatus.active,
        startedAt: now,
      );
      final state = CallViewState(session: session);

      expect(state.copyWith().session, same(session));
      expect(state.copyWith(session: null).session, isNull);
    });
  });
}
