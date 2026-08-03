import 'dart:convert';

import 'package:aphrodite/chat/application/message_sender.dart';
import 'package:aphrodite/chat/data/chat_api.dart';
import 'package:aphrodite/chat/e2ee/e2ee_client.dart';
import 'package:aphrodite/chat/models/message.dart';
import 'package:aphrodite/core/network/network_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encrypts plaintext locally and sends a stable idempotent envelope',
      () async {
    final network = _RecordingNetworkClient();
    final encryption = _RecordingE2eeClient();
    final sender = MessageSender(
      api: ChatApi(networkClient: network),
      encryption: encryption,
    );

    final message = await sender.sendText(
      conversationId: 'conversation-example',
      senderId: 'account-self',
      clientMessageId: 'client-message-example',
      text: 'Hello',
      replyToMessageId: 'reply-example',
      createdAt: DateTime.parse('2026-08-03T03:00:00Z'),
    );

    expect(encryption.conversationId, 'conversation-example');
    final plaintext =
        jsonDecode(utf8.decode(encryption.plaintext!)) as Map<String, dynamic>;
    expect(plaintext['content'], 'Hello');
    expect(plaintext['client_message_id'], 'client-message-example');
    expect(plaintext['reply_to'], 'reply-example');
    expect(network.postData, {
      'client_message_id': 'client-message-example',
      'kind': 'text',
      'ciphertext': 'AQID',
      'encryption': {
        'scheme': 'mls_v1',
        'group_id': 'group-example',
        'epoch': 7,
        'header': 'BAU',
      },
      'reply_to': 'reply-example',
    });
    expect(message.id, 'message-confirmed');
    expect(message.clientMessageId, 'client-message-example');
    expect(message.text, 'Hello');
    expect(message.encryptionState, MessageEncryptionState.plain);
    expect(message.status, ChatMessageStatus.sent);
  });

  test('rejects a response for a different client message', () async {
    final network = _RecordingNetworkClient(
      responseClientMessageId: 'different-client-message',
    );
    final sender = MessageSender(
      api: ChatApi(networkClient: network),
      encryption: _RecordingE2eeClient(),
    );

    expect(
      () => sender.sendText(
        conversationId: 'conversation-example',
        senderId: 'account-self',
        clientMessageId: 'client-message-example',
        text: 'Hello',
      ),
      throwsA(isA<ChatSendProtocolException>()),
    );
  });

  test('rejects empty identifiers before encryption or network access',
      () async {
    final network = _RecordingNetworkClient();
    final encryption = _RecordingE2eeClient();
    final sender = MessageSender(
      api: ChatApi(networkClient: network),
      encryption: encryption,
    );

    await expectLater(
      () => sender.sendText(
        conversationId: ' ',
        senderId: 'account-self',
        clientMessageId: 'client-message-example',
        text: 'Hello',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(encryption.plaintext, isNull);
    expect(network.postData, isNull);
  });
}

class _RecordingE2eeClient implements E2eeClient {
  String? conversationId;
  List<int>? plaintext;

  @override
  Future<EncryptedPayload> encryptMessage({
    required String conversationId,
    required List<int> plaintext,
  }) async {
    this.conversationId = conversationId;
    this.plaintext = List<int>.from(plaintext);
    return EncryptedPayload(
      ciphertext: const [1, 2, 3],
      scheme: 'mls_v1',
      groupId: 'group-example',
      epoch: 7,
      header: const [4, 5],
    );
  }

  @override
  Future<List<int>> decryptMessage({
    required String conversationId,
    required EncryptedPayload payload,
  }) {
    throw UnimplementedError();
  }
}

class _RecordingNetworkClient implements NetworkClient {
  _RecordingNetworkClient({
    this.responseClientMessageId = 'client-message-example',
  });

  final String responseClientMessageId;
  Map<String, Object?>? postData;

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    postData = data as Map<String, Object?>;
    return {
      'request_id': 'request-example',
      'data': {
        'id': 'message-confirmed',
        'conversation_id': 'conversation-example',
        'sender_id': 'account-self',
        'client_message_id': responseClientMessageId,
        'kind': 'text',
        'ciphertext': 'AQID',
        'reply_to': 'reply-example',
        'created_at': '2026-08-03T03:00:01Z',
        'edited_at': null,
        'deleted_at': null,
      },
      'meta': {'next_cursor': null},
    };
  }

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? queryParameters,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Object?> put(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Object?> delete(
    String path, {
    Map<String, Object?>? queryParameters,
  }) {
    throw UnimplementedError();
  }
}
