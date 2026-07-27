import 'package:flutter/material.dart';

class VoiceMessageBubble extends StatefulWidget {
  const VoiceMessageBubble({
    required this.duration,
    required this.foregroundColor,
    super.key,
  });

  final Duration duration;
  final Color foregroundColor;

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  bool _playing = false;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _playing = !_playing),
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: widget.foregroundColor,
                inactiveTrackColor: widget.foregroundColor.withValues(alpha: 0.3),
                thumbColor: widget.foregroundColor,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: _progress,
                onChanged: (value) => setState(() => _progress = value),
              ),
            ),
          ),
          Text(
            '0:${widget.duration.inSeconds.toString().padLeft(2, '0')}',
            style: TextStyle(color: widget.foregroundColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
