import 'package:flutter/material.dart';

import '../models/message.dart';
import 'voice_message_bubble.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, required this.isMine, super.key});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isMine ? scheme.primary : scheme.surfaceContainerHigh;
    final foreground = isMine ? scheme.onPrimary : scheme.onSurface;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: message.kind == ChatMessageKind.audio
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : const EdgeInsets.fromLTRB(14, 10, 12, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 5),
          bottomRight: Radius.circular(isMine ? 5 : 18),
        ),
      ),
      child: message.kind == ChatMessageKind.audio
          ? VoiceMessageBubble(
              duration:
                  Duration(seconds: int.tryParse(message.text ?? '') ?? 0),
              foregroundColor: foreground,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(message.text ?? '', style: TextStyle(color: foreground)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          color: foreground.withValues(alpha: 0.72), fontSize: 10),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.status == ChatMessageStatus.sending
                            ? Icons.schedule
                            : message.status == ChatMessageStatus.failed
                                ? Icons.error_outline
                                : Icons.done_all,
                        size: 14,
                        color: foreground.withValues(alpha: 0.8),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}
