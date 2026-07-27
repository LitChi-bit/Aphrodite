import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../models/call.dart';
import '../models/conversation.dart';
import '../providers/call_provider.dart';
import '../providers/messages_provider.dart';
import 'chat_input.dart';
import 'message_list.dart';

class ChatRoomScreen extends ConsumerWidget {
  const ChatRoomScreen({required this.conversation, super.key});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(messagesProvider(conversation.id));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              child: Text(conversation.title.characters.isEmpty
                  ? '?'
                  : conversation.title.characters.first),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conversation.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Row(
                    children: [
                      Icon(Icons.lock,
                          size: 11,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 3),
                      Text(
                        conversation.encryptionState ==
                                ConversationEncryptionState.ready
                            ? '端到端加密'
                            : '加密组件待接入',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
              onPressed: () => _startCall(context, ref, CallKind.audio),
              icon: const Icon(Icons.call_outlined),
              tooltip: '语音通话'),
          IconButton(
              onPressed: () => _startCall(context, ref, CallKind.video),
              icon: const Icon(Icons.videocam_outlined),
              tooltip: '视频通话'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: FilledButton.tonal(
                  onPressed: () => ref
                      .read(messagesProvider(conversation.id).notifier)
                      .load(),
                  child: const Text('重新加载'),
                ),
              ),
              data: (items) => MessageList(messages: items),
            ),
          ),
          ChatInput(
            onSend: (value) => ref
                .read(messagesProvider(conversation.id).notifier)
                .sendText(value),
          ),
        ],
      ),
    );
  }

  void _startCall(BuildContext context, WidgetRef ref, CallKind kind) {
    ref.read(callProvider.notifier).start(
          conversationId: conversation.id,
          kind: kind,
        );
    Navigator.of(context).pushNamed(
      AppRouter.call,
      arguments: conversation.title,
    );
  }
}
