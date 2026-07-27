import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/message_repository.dart';
import '../models/conversation.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => DemoMessageRepository(),
);

final conversationsProvider =
    FutureProvider.autoDispose<List<Conversation>>((ref) async {
  return ref.watch(messageRepositoryProvider).loadConversations();
});
