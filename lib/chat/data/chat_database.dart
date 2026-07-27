import '../models/conversation.dart';
import '../models/message.dart';

abstract interface class ChatDatabase {
  Future<List<Conversation>> readConversations({int limit = 50});

  Future<List<ChatMessage>> readMessages(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
  });

  Future<void> saveMessages(List<ChatMessage> messages);

  Future<void> savePendingMessage(ChatMessage message);

  Future<void> replacePendingMessage(
    String clientMessageId,
    ChatMessage confirmed,
  );
}
