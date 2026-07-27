import 'package:flutter/material.dart';

import 'voice_record_button.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({required this.onSend, super.key});

  final ValueChanged<String> onSend;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onSend(value);
    _controller.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add_circle_outline),
                tooltip: '添加附件',
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '输入消息',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onChanged: (value) {
                    final hasText = value.trim().isNotEmpty;
                    if (_hasText != hasText) setState(() => _hasText = hasText);
                  },
                ),
              ),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: _hasText
                    ? IconButton.filled(
                        key: const ValueKey('send'),
                        onPressed: _send,
                        icon: const Icon(Icons.arrow_upward),
                        tooltip: '发送',
                      )
                    : VoiceRecordButton(
                        key: const ValueKey('voice'),
                        onRecorded: (duration) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    '已录制 ${duration.inSeconds} 秒语音（等待媒体服务接入）')),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
