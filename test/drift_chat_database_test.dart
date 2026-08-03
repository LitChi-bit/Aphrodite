import 'dart:convert';
import 'dart:typed_data';

import 'package:aphrodite/chat/data/drift_chat_database.dart';
import 'package:aphrodite/chat/models/conversation.dart';
import 'package:aphrodite/chat/models/message.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _TestRecordCodec codec;
  late DriftChatDatabase database;

  setUp(() {
    codec = _TestRecordCodec();
    database = DriftChatDatabase(NativeDatabase.memory(), codec: codec);
  });

  tearDown(() => database.close());

  test('stores conversations as sealed records and reads latest first',
      () async {
    await database.saveConversations([
      _conversation('conversation-old', DateTime.utc(2026, 8, 3, 2)),
      _conversation('conversation-new', DateTime.utc(2026, 8, 3, 3)),
    ]);

    final conversations = await database.readConversations();
    final records = await database.select(database.chatRecords).get();

    expect(conversations.map((item) => item.id), [
      'conversation-new',
      'conversation-old',
    ]);
    expect(records.every((record) => record.sealedRecord.isNotEmpty), isTrue);
    final plaintextTitleBytes = utf8.encode('Example conversation');
    expect(
      records.every(
        (record) => !_containsBytes(record.sealedRecord, plaintextTitleBytes),
      ),
      isTrue,
    );
  });

  test('replaces a pending message by client message id', () async {
    final pending = _message(
      id: 'pending-client-example',
      clientMessageId: 'client-example',
      status: ChatMessageStatus.sending,
      text: 'Local plaintext',
      createdAt: DateTime.utc(2026, 8, 3, 2),
    );
    final confirmed = _message(
      id: 'message-confirmed',
      clientMessageId: 'client-example',
      status: ChatMessageStatus.sent,
      text: 'Local plaintext',
      createdAt: DateTime.utc(2026, 8, 3, 3),
    );

    await database.savePendingMessage(pending);
    await database.replacePendingMessage('client-example', confirmed);
    final messages = await database.readMessages('conversation-example');

    expect(messages, hasLength(1));
    expect(messages.single.id, 'message-confirmed');
    expect(messages.single.status, ChatMessageStatus.sent);
  });

  test('paginates messages from the local cursor message', () async {
    await database.saveMessages([
      _message(
        id: 'message-one',
        clientMessageId: 'client-one',
        status: ChatMessageStatus.sent,
        text: 'One',
        createdAt: DateTime.utc(2026, 8, 3, 1),
      ),
      _message(
        id: 'message-two',
        clientMessageId: 'client-two',
        status: ChatMessageStatus.sent,
        text: 'Two',
        createdAt: DateTime.utc(2026, 8, 3, 2),
      ),
      _message(
        id: 'message-three',
        clientMessageId: 'client-three',
        status: ChatMessageStatus.sent,
        text: 'Three',
        createdAt: DateTime.utc(2026, 8, 3, 3),
      ),
    ]);

    final firstPage =
        await database.readMessages('conversation-example', limit: 2);
    final secondPage = await database.readMessages(
      'conversation-example',
      beforeMessageId: firstPage.last.id,
      limit: 2,
    );

    expect(firstPage.map((message) => message.id), [
      'message-three',
      'message-two',
    ]);
    expect(secondPage.map((message) => message.id), ['message-one']);
  });
}

Conversation _conversation(String id, DateTime updatedAt) => Conversation(
      id: id,
      kind: ConversationKind.direct,
      title: 'Example conversation',
      participantIds: const ['account-self', 'account-other'],
      encryptionState: ConversationEncryptionState.ready,
      createdAt: updatedAt.subtract(const Duration(days: 1)),
      updatedAt: updatedAt,
    );

ChatMessage _message({
  required String id,
  required String clientMessageId,
  required ChatMessageStatus status,
  required String text,
  required DateTime createdAt,
}) =>
    ChatMessage(
      id: id,
      conversationId: 'conversation-example',
      senderId: 'account-self',
      clientMessageId: clientMessageId,
      kind: ChatMessageKind.text,
      status: status,
      encryptionState: MessageEncryptionState.plain,
      text: text,
      createdAt: createdAt,
    );

bool _containsBytes(List<int> value, List<int> expected) {
  if (expected.isEmpty || expected.length > value.length) return false;
  for (var start = 0; start <= value.length - expected.length; start++) {
    var matched = true;
    for (var index = 0; index < expected.length; index++) {
      if (value[start + index] != expected[index]) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}

class _TestRecordCodec implements ChatRecordCodec {
  @override
  Future<Map<String, dynamic>> open(Uint8List sealedRecord) async {
    final encoded = utf8.decode(
      sealedRecord.map((value) => value ^ 0xA5).toList(),
    );
    return jsonDecode(encoded) as Map<String, dynamic>;
  }

  @override
  Future<Uint8List> seal(Map<String, dynamic> record) async {
    final encoded = utf8.encode(jsonEncode(record));
    return Uint8List.fromList(encoded.map((value) => value ^ 0xA5).toList());
  }
}
