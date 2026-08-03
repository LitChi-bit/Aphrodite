import 'package:drift/drift.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import 'chat_database.dart';

part 'drift_chat_database.g.dart';

abstract interface class ChatRecordCodec {
  Future<Uint8List> seal(Map<String, dynamic> record);

  Future<Map<String, dynamic>> open(Uint8List sealedRecord);
}

class ChatRecords extends Table {
  TextColumn get id => text()();

  TextColumn get recordType => text()();

  TextColumn get conversationId => text().nullable()();

  TextColumn get clientMessageId => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  BlobColumn get sealedRecord => blob()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [ChatRecords])
class DriftChatDatabase extends _$DriftChatDatabase implements ChatDatabase {
  DriftChatDatabase(super.executor, {required ChatRecordCodec codec})
      : _codec = codec;

  final ChatRecordCodec _codec;

  static const _conversationType = 'conversation';
  static const _messageType = 'message';

  @override
  int get schemaVersion => 1;

  @override
  Future<List<Conversation>> readConversations({int limit = 50}) async {
    _validateLimit(limit);
    final records = await (select(chatRecords)
          ..where((row) => row.recordType.equals(_conversationType))
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
          ..limit(limit))
        .get();
    return Future.wait(
      records.map((record) async => Conversation.fromJson(
            await _codec.open(record.sealedRecord),
          )),
    );
  }

  @override
  Future<List<ChatMessage>> readMessages(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
  }) async {
    _validateValue(conversationId, 'conversationId');
    _validateLimit(limit);
    final records = await (select(chatRecords)
          ..where(
            (row) =>
                row.recordType.equals(_messageType) &
                row.conversationId.equals(conversationId),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .get();
    final messages = await Future.wait(
      records.map(
        (record) async =>
            ChatMessage.fromJson(await _codec.open(record.sealedRecord)),
      ),
    );
    messages.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    final start = beforeMessageId == null
        ? 0
        : messages.indexWhere((message) => message.id == beforeMessageId) + 1;
    if (start <= 0 || start >= messages.length) {
      return start >= messages.length
          ? const []
          : messages.take(limit).toList();
    }
    return messages.skip(start).take(limit).toList();
  }

  @override
  Future<void> saveMessages(List<ChatMessage> messages) async {
    await transaction(() async {
      for (final message in messages) {
        await _saveMessage(message);
      }
    });
  }

  @override
  Future<void> savePendingMessage(ChatMessage message) => _saveMessage(message);

  @override
  Future<void> replacePendingMessage(
    String clientMessageId,
    ChatMessage confirmed,
  ) async {
    _validateValue(clientMessageId, 'clientMessageId');
    if (confirmed.clientMessageId != clientMessageId) {
      throw ArgumentError.value(
        confirmed.clientMessageId,
        'confirmed.clientMessageId',
        'Confirmed message does not match the pending message.',
      );
    }
    await transaction(() async {
      await (delete(chatRecords)
            ..where(
              (row) =>
                  row.recordType.equals(_messageType) &
                  row.clientMessageId.equals(clientMessageId),
            ))
          .go();
      await _saveMessage(confirmed);
    });
  }

  Future<void> saveConversations(List<Conversation> conversations) async {
    await transaction(() async {
      for (final conversation in conversations) {
        final sealed = await _codec.seal(conversation.toJson());
        await into(chatRecords).insertOnConflictUpdate(
          ChatRecordsCompanion.insert(
            id: conversation.id,
            recordType: _conversationType,
            updatedAt: conversation.updatedAt.toUtc(),
            sealedRecord: sealed,
          ),
        );
      }
    });
  }

  Future<void> _saveMessage(ChatMessage message) async {
    final sealed = await _codec.seal(message.toJson());
    await into(chatRecords).insertOnConflictUpdate(
      ChatRecordsCompanion.insert(
        id: message.id,
        recordType: _messageType,
        conversationId: Value(message.conversationId),
        clientMessageId: Value(message.clientMessageId),
        updatedAt: message.createdAt.toUtc(),
        sealedRecord: sealed,
      ),
    );
  }

  static void _validateValue(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty');
    }
  }

  static void _validateLimit(int limit) {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(
          limit, 'limit', 'limit must be between 1 and 200');
    }
  }
}
