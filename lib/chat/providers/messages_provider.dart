import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/message_repository.dart';
import '../models/message.dart';
import 'conversations_provider.dart';

final messagesProvider = StateNotifierProvider.autoDispose
    .family<MessagesNotifier, AsyncValue<List<ChatMessage>>, String>(
  (ref, conversationId) => MessagesNotifier(
    conversationId: conversationId,
    repository: ref.watch(messageRepositoryProvider),
  )..load(),
);

class MessagesNotifier extends StateNotifier<AsyncValue<List<ChatMessage>>> {
  MessagesNotifier({required this.conversationId, required this.repository})
      : super(const AsyncValue.loading());

  final String conversationId;
  final MessageRepository repository;
  static const Uuid _uuid = Uuid();

  Future<void> load() async {
    state = await AsyncValue.guard(
      () => repository.loadMessages(conversationId),
    );
  }

  Future<void> sendText(String value, {String? replyToMessageId}) async {
    final text = value.trim();
    if (text.isEmpty) return;
    final current = state.valueOrNull ?? const <ChatMessage>[];
    final clientId = _uuid.v4();
    final pending = ChatMessage(
      id: 'pending-$clientId',
      conversationId: conversationId,
      senderId: 'self',
      clientMessageId: clientId,
      kind: ChatMessageKind.text,
      status: ChatMessageStatus.sending,
      encryptionState: MessageEncryptionState.plain,
      text: text,
      replyToMessageId: replyToMessageId,
      createdAt: DateTime.now(),
    );
    state = AsyncValue.data([...current, pending]);
    try {
      final sent = await repository.sendText(
        conversationId: conversationId,
        clientMessageId: clientId,
        text: text,
        replyToMessageId: replyToMessageId,
      );
      state = AsyncValue.data([
        for (final message in state.valueOrNull ?? const <ChatMessage>[])
          if (message.clientMessageId == clientId) sent else message,
      ]);
    } catch (error, stackTrace) {
      state = AsyncValue.data([
        for (final message in state.valueOrNull ?? const <ChatMessage>[])
          if (message.clientMessageId == clientId)
            message.copyWith(
              status: ChatMessageStatus.failed,
              failureReason: error.toString(),
            )
          else
            message,
      ]);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
