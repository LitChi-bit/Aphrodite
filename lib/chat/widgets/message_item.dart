import 'package:flutter/material.dart';

import '../models/message.dart';
import 'message_bubble.dart';

class MessageItem extends StatelessWidget {
  const MessageItem({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.senderId == 'self';
    return Semantics(
      label: mine ? '我发送的消息' : '收到的消息',
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(
            left: mine ? 54 : 12,
            right: mine ? 12 : 54,
            top: 4,
            bottom: 4,
          ),
          child: MessageBubble(message: message, isMine: mine),
        ),
      ),
    );
  }
}
