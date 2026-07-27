import '../data/chat_database.dart';
import '../models/message.dart';

abstract interface class RemoteMessageSource {
  Future<SyncPage> synchronize({
    required String conversationId,
    String? cursor,
    List<int> missingSequences = const [],
    int limit = 200,
  });
}

class MessageSyncService {
  const MessageSyncService({
    required RemoteMessageSource remote,
    required ChatDatabase database,
  })  : _remote = remote,
        _database = database;

  final RemoteMessageSource _remote;
  final ChatDatabase _database;

  Future<SyncPage> synchronize({
    required String conversationId,
    String? cursor,
    List<int> missingSequences = const [],
  }) async {
    final page = await _remote.synchronize(
      conversationId: conversationId,
      cursor: cursor,
      missingSequences: missingSequences,
    );
    await _database.saveMessages(page.messages);
    return page;
  }
}

class SyncPage {
  SyncPage({required List<ChatMessage> messages, required this.nextCursor})
      : messages = List.unmodifiable(messages);

  final List<ChatMessage> messages;
  final String? nextCursor;
}
