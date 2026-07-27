import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/call_provider.dart';

class CallScreen extends ConsumerWidget {
  const CallScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callProvider);
    final session = state.session;
    return Scaffold(
      backgroundColor: const Color(0xFF101116),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          session == null ? '正在连接…' : '媒体加密组件待接入',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: constraints.maxWidth > 600 ? 3 : 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: .78,
                        ),
                        itemCount: 2,
                        itemBuilder: (context, index) => Container(
                          decoration: BoxDecoration(
                            color: index == 0
                                ? const Color(0xFF28304A)
                                : const Color(0xFF332942),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Center(
                            child: CircleAvatar(
                              radius: 38,
                              backgroundColor: Colors.white12,
                              child: Text(
                                  index == 0
                                      ? '我'
                                      : title.characters.isEmpty
                                          ? '?'
                                          : title.characters.first,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 24)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const _CallControls(),
                ],
              ),
            ),
            if (state.isReconnecting)
              const Positioned(
                  top: 8, left: 16, right: 16, child: _ReconnectBanner()),
          ],
        ),
      ),
    );
  }
}

class _CallControls extends ConsumerWidget {
  const _CallControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Control(
              icon: state.microphoneEnabled ? Icons.mic : Icons.mic_off,
              label: '麦克风',
              active: state.microphoneEnabled,
              onTap: () => ref.read(callProvider.notifier).toggleMicrophone()),
          _Control(
              icon: state.cameraEnabled ? Icons.videocam : Icons.videocam_off,
              label: '摄像头',
              active: state.cameraEnabled,
              onTap: () => ref.read(callProvider.notifier).toggleCamera()),
          _Control(
              icon: state.speakerEnabled ? Icons.volume_up : Icons.hearing,
              label: '扬声器',
              active: state.speakerEnabled,
              onTap: () => ref.read(callProvider.notifier).toggleSpeaker()),
          _Control(
              icon: Icons.call_end,
              label: '挂断',
              destructive: true,
              onTap: () {
                ref.read(callProvider.notifier).end();
                Navigator.of(context).pop();
              }),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.active = true,
      this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            style: IconButton.styleFrom(
                backgroundColor: destructive
                    ? Colors.redAccent
                    : active
                        ? Colors.white24
                        : Colors.white10,
                foregroundColor: Colors.white),
            onPressed: onTap,
            icon: Icon(icon),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();
  @override
  Widget build(BuildContext context) => const Material(
        color: Colors.amber,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('网络不稳定，正在恢复连接…', textAlign: TextAlign.center),
        ),
      );
}
