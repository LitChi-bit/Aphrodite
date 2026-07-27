import 'package:flutter/material.dart';

class CallOverlay extends StatelessWidget {
  const CallOverlay({required this.title, required this.onTap, super.key});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Theme.of(context).colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(18),
            elevation: 8,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.call, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 8),
                    Text('$title · 通话中',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onInverseSurface)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
