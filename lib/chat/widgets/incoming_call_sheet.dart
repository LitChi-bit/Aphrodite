import 'package:flutter/material.dart';

class IncomingCallSheet extends StatelessWidget {
  const IncomingCallSheet(
      {required this.callerName,
      required this.onAccept,
      required this.onDecline,
      super.key});

  final String callerName;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 24),
              CircleAvatar(
                  radius: 38,
                  child: Text(
                      callerName.characters.isEmpty
                          ? '?'
                          : callerName.characters.first,
                      style: const TextStyle(fontSize: 26))),
              const SizedBox(height: 12),
              Text(callerName,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Text('邀请你进行通话'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton.tonalIcon(
                      onPressed: onDecline,
                      icon: const Icon(Icons.call_end),
                      label: const Text('拒绝')),
                  FilledButton.icon(
                      onPressed: onAccept,
                      icon: const Icon(Icons.call),
                      label: const Text('接听')),
                ],
              ),
            ],
          ),
        ),
      );
}
