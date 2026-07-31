import 'package:aphrodite/chat/data/chat_api.dart';
import 'package:aphrodite/chat/models/conversation.dart';
import 'package:aphrodite/chat/models/message.dart';
import 'package:aphrodite/core/network/network_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversation response maps snake case fields and cursor', () async {
    final client = _StubNetworkClient(
      getResponse: {
        'request_id': 'request-example',
        'data': [
          {
            'id': 'conversation-example',
            'kind': 'group',
            'name': 'Example group',
            'member_ids': ['account-self', 'account-other'],
            'last_message_preview': 'Local decrypted preview',
            'last_message_at': '2026-07-27T06:00:00Z',
            'unread_count': 2,
            'muted': true,
            'pinned': false,
            'encryption_scheme': 'mls_v1',
            'created_at': '2026-07-01T00:00:00Z',
            'updated_at': '2026-07-27T06:00:00Z',
          },
        ],
        'meta': {'next_cursor': 'cursor-example'},
      },
    );

    final page = await ChatApi(networkClient: client).getConversations();
    final conversation = page.items.single.toDomain();

    expect(page.nextCursor, 'cursor-example');
    expect(conversation.id, 'conversation-example');
    expect(conversation.kind, ConversationKind.group);
    expect(conversation.title, 'Example group');
    expect(conversation.unreadCount, 2);
    expect(conversation.isMuted, isTrue);
    expect(conversation.encryptionState, ConversationEncryptionState.ready);
    expect(client.lastPath, '/v1/conversations');
  });

  test('encrypted message remains ciphertext-only until decrypted', () async {
    final client = _StubNetworkClient(
      getResponse: {
        'request_id': 'request-example',
        'data': [
          {
            'id': 'message-example',
            'conversation_id': 'conversation-example',
            'sender_id': 'account-other',
            'client_message_id': 'client-message-example',
            'kind': 'text',
            'ciphertext': 'base64-example-ciphertext',
            'reply_to': null,
            'created_at': '2026-07-27T06:00:00Z',
            'edited_at': null,
            'deleted_at': null,
          },
        ],
        'meta': {'next_cursor': null},
      },
    );

    final page = await ChatApi(networkClient: client).getMessages(
      conversationId: 'conversation-example',
    );
    final message = page.items.single.toDomain();

    expect(message.text, isNull);
    expect(message.encryptionState, MessageEncryptionState.encrypted);
    expect(message.status, ChatMessageStatus.sent);
    expect(client.lastPath, '/v1/conversations/conversation-example/messages');
    expect(client.lastQuery?['direction'], 'backward');
  });

  test('send response maps a decrypted local projection when provided',
      () async {
    final client = _StubNetworkClient(
      postResponse: {
        'request_id': 'request-example',
        'data': {
          'id': 'message-confirmed',
          'conversation_id': 'conversation-example',
          'sender_id': 'account-self',
          'client_message_id': 'client-message-example',
          'kind': 'text',
          'ciphertext': 'base64-example-ciphertext',
          'decrypted_text': 'Example message',
          'reply_to': null,
          'created_at': '2026-07-27T06:00:00Z',
          'edited_at': null,
          'deleted_at': null,
        },
        'meta': {'next_cursor': null},
      },
    );

    final dto = await ChatApi(networkClient: client).sendMessage(
      conversationId: 'conversation-example',
      encryptedEnvelope: {
        'client_message_id': 'client-message-example',
        'kind': 'text',
        'ciphertext': 'base64-example-ciphertext',
      },
    );
    final message = dto.toDomain();

    expect(message.text, 'Example message');
    expect(message.encryptionState, MessageEncryptionState.plain);
    expect(client.lastPostData?['ciphertext'], 'base64-example-ciphertext');
  });

  test('malformed API response is rejected', () async {
    final client = _StubNetworkClient(getResponse: const ['not-an-envelope']);

    expect(
      () => ChatApi(networkClient: client).getConversations(),
      throwsA(isA<FormatException>()),
    );
  });

  test('conversation DTO rejects invalid protocol field types', () async {
    final client = _StubNetworkClient(
      getResponse: {
        'request_id': 'request-example',
        'data': [
          {
            'id': 'conversation-example',
            'kind': 'group',
            'name': 'Example group',
            'member_ids': ['account-self', 42],
            'unread_count': -1,
            'created_at': 'not-a-date',
          },
        ],
      },
    );

    expect(
      () => ChatApi(networkClient: client).getConversations(),
      throwsA(isA<FormatException>()),
    );
  });

  test('message DTO rejects unknown kinds and malformed timestamps', () async {
    final client = _StubNetworkClient(
      getResponse: {
        'request_id': 'request-example',
        'data': [
          {
            'id': 'message-example',
            'conversation_id': 'conversation-example',
            'sender_id': 'account-other',
            'client_message_id': 'client-message-example',
            'kind': 'unknown',
            'ciphertext': 'base64-example-ciphertext',
            'created_at': 'not-a-date',
          },
        ],
      },
    );

    expect(
        () => ChatApi(networkClient: client).getMessages(
              conversationId: 'conversation-example',
            ),
        throwsA(isA<FormatException>()));
  });
}

class _StubNetworkClient implements NetworkClient {
  _StubNetworkClient({this.getResponse, this.postResponse});

  final Object? getResponse;
  final Object? postResponse;
  String? lastPath;
  Map<String, Object?>? lastQuery;
  Map<String, Object?>? lastPostData;

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    lastPath = path;
    lastQuery = queryParameters;
    return getResponse;
  }

  @override
  Future<Object?> delete(
    String path, {
    Map<String, Object?>? queryParameters,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    lastPath = path;
    lastQuery = queryParameters;
    lastPostData = data as Map<String, Object?>?;
    return postResponse;
  }
}
