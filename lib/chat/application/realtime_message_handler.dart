import '../data/chat_database.dart';
import '../models/message.dart';

class RealtimeMessageHandler {
  const RealtimeMessageHandler({required ChatDatabase database})
      : _database = database;

  final ChatDatabase _database;

  Future<void> handle(RealtimeEvent event) async {
    switch (event) {
      case MessageCreatedEvent(:final message):
        await _database.saveMessages([message]);
      case MessageConfirmedEvent(:final clientMessageId, :final message):
        await _database.replacePendingMessage(clientMessageId, message);
      case UnsupportedRealtimeEvent():
        return;
    }
  }
}

sealed class RealtimeEvent {
  const RealtimeEvent({required this.eventId});

  final String eventId;
}

class MessageCreatedEvent extends RealtimeEvent {
  const MessageCreatedEvent({required super.eventId, required this.message});

  final ChatMessage message;
}

class MessageConfirmedEvent extends RealtimeEvent {
  const MessageConfirmedEvent({
    required super.eventId,
    required this.clientMessageId,
    required this.message,
  });

  final String clientMessageId;
  final ChatMessage message;
}

class UnsupportedRealtimeEvent extends RealtimeEvent {
  const UnsupportedRealtimeEvent({required super.eventId});
}
