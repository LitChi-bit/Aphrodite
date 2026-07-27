import 'package:flutter/material.dart';

import '../models/message.dart';
import 'message_item.dart';

class MessageList extends StatelessWidget {
  const MessageList({required this.messages, super.key});

  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 12),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        return AnimatedSwitcher(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, child: child),
          ),
          child: MessageItem(key: ValueKey(message.id), message: message),
        );
      },
    );
  }
}
