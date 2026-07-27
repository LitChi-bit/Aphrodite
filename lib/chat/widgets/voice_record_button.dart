import 'package:flutter/material.dart';

class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({required this.onRecorded, super.key});

  final ValueChanged<Duration> onRecorded;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  DateTime? _startedAt;
  bool _cancelled = false;

  void _start(LongPressStartDetails details) {
    setState(() {
      _startedAt = DateTime.now();
      _cancelled = false;
    });
  }

  void _move(LongPressMoveUpdateDetails details) {
    final shouldCancel = details.offsetFromOrigin.dy < -72;
    if (_cancelled != shouldCancel) setState(() => _cancelled = shouldCancel);
  }

  void _end(LongPressEndDetails details) {
    final startedAt = _startedAt;
    if (startedAt != null && !_cancelled) {
      widget.onRecorded(DateTime.now().difference(startedAt));
    }
    setState(() {
      _startedAt = null;
      _cancelled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _start,
      onLongPressMoveUpdate: _move,
      onLongPressEnd: _end,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: _startedAt == null
              ? Colors.transparent
              : _cancelled
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(_cancelled ? Icons.delete_outline : Icons.mic_none),
      ),
    );
  }
}
