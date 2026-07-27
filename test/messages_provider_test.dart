import 'dart:async';

import 'package:aphrodite/chat/data/message_repository.dart';
import 'package:aphrodite/chat/models/conversation.dart';
import 'package:aphrodite/chat/models/message.dart';
import 'package:aphrodite/chat/providers/messages_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty text is ignored', () async {
    final repository = _ControlledMessageRepository();
    final notifier = MessagesNotifier(
      conversationId: 'conversation-a',
      repository: repository,
    );
    addTearDown(notifier.dispose);

    await notifier.sendText('   ');

    expect(repository.sendCalls, 0);
    expect(notifier.state.valueOrNull, isNull);
  });

  test('pending message is replaced by the confirmed message', () async {
    final repository = _ControlledMessageRepository();
    final notifier = MessagesNotifier(
      conversationId: 'conversation-a',
      repository: repository,
    );
    addTearDown(notifier.dispose);

    final send = notifier.sendText('  Hello  ');
    final pending = notifier.state.requireValue.single;

    expect(pending.status, ChatMessageStatus.sending);
    expect(pending.text, 'Hello');
    expect(pending.conversationId, 'conversation-a');

    repository.completeSend();
    await send;

    final sent = notifier.state.requireValue.single;
    expect(sent.status, ChatMessageStatus.sent);
    expect(sent.id, 'confirmed-${pending.clientMessageId}');
    expect(sent.clientMessageId, pending.clientMessageId);
  });

  test('failed send keeps the message and marks it failed', () async {
    final repository = _ControlledMessageRepository();
    final notifier = MessagesNotifier(
      conversationId: 'conversation-a',
      repository: repository,
    );
    addTearDown(notifier.dispose);

    final send = notifier.sendText('Hello');
    final clientMessageId = notifier.state.requireValue.single.clientMessageId;

    repository.failSend(const _TestFailure());
    await expectLater(send, throwsA(isA<_TestFailure>()));

    final failed = notifier.state.requireValue.single;
    expect(failed.clientMessageId, clientMessageId);
    expect(failed.status, ChatMessageStatus.failed);
    expect(failed.failureReason, contains('controlled failure'));
  });

  test('notifiers keep conversation state isolated', () async {
    final repositoryA = _ControlledMessageRepository();
    final repositoryB = _ControlledMessageRepository();
    final notifierA = MessagesNotifier(
      conversationId: 'conversation-a',
      repository: repositoryA,
    );
    final notifierB = MessagesNotifier(
      conversationId: 'conversation-b',
      repository: repositoryB,
    );
    addTearDown(notifierA.dispose);
    addTearDown(notifierB.dispose);

    final sendA = notifierA.sendText('Only A');

    expect(
        notifierA.state.requireValue.single.conversationId, 'conversation-a');
    expect(notifierB.state.valueOrNull, isNull);
    expect(repositoryB.sendCalls, 0);

    repositoryA.completeSend();
    await sendA;
  });
}

class _ControlledMessageRepository implements MessageRepository {
  final Completer<ChatMessage> _sendCompleter = Completer<ChatMessage>();
  String? _conversationId;
  String? _clientMessageId;
  String? _text;
  String? _replyToMessageId;
  int sendCalls = 0;

  @override
  Future<List<Conversation>> loadConversations() async => const [];

  @override
  Future<List<ChatMessage>> loadMessages(String conversationId) async =>
      const [];

  @override
  Future<ChatMessage> sendText({
    required String conversationId,
    required String clientMessageId,
    required String text,
    String? replyToMessageId,
  }) {
    sendCalls += 1;
    _conversationId = conversationId;
    _clientMessageId = clientMessageId;
    _text = text;
    _replyToMessageId = replyToMessageId;
    return _sendCompleter.future;
  }

  void completeSend() {
    _sendCompleter.complete(
      ChatMessage(
        id: 'confirmed-$_clientMessageId',
        conversationId: _conversationId!,
        senderId: 'self',
        clientMessageId: _clientMessageId!,
        kind: ChatMessageKind.text,
        status: ChatMessageStatus.sent,
        encryptionState: MessageEncryptionState.plain,
        text: _text,
        replyToMessageId: _replyToMessageId,
        createdAt: DateTime(2026, 7, 27),
      ),
    );
  }

  void failSend(Object error) => _sendCompleter.completeError(error);
}

class _TestFailure implements Exception {
  const _TestFailure();

  @override
  String toString() => 'controlled failure';
}
