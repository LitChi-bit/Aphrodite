import 'package:flutter/material.dart';

class PluginUiRenderer extends StatelessWidget {
  const PluginUiRenderer({required this.descriptor, super.key});

  final Map<String, Object?> descriptor;

  @override
  Widget build(BuildContext context) => _render(context, descriptor, 0);

  Widget _render(BuildContext context, Map<String, Object?> node, int depth) {
    if (depth > 12) return const _UnsupportedNode(label: '层级过深');
    final type = node['type'];
    return switch (type) {
      'text' => Text(node['text'] as String? ?? ''),
      'button' => FilledButton.tonal(
          onPressed: () {},
          child: Text(node['label'] as String? ?? '按钮'),
        ),
      'card' => Card(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: _children(context, node, depth))),
      'row' => Row(
          mainAxisSize: MainAxisSize.min,
          children: _childList(context, node, depth)),
      'column' => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _childList(context, node, depth)),
      _ => _UnsupportedNode(label: '不支持的组件：${type ?? 'unknown'}'),
    };
  }

  Widget _children(
          BuildContext context, Map<String, Object?> node, int depth) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: _childList(context, node, depth),
      );

  List<Widget> _childList(
      BuildContext context, Map<String, Object?> node, int depth) {
    final raw = node['children'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().take(100).map((child) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: _render(context, child.cast<String, Object?>(), depth + 1),
      );
    }).toList();
  }
}

class _UnsupportedNode extends StatelessWidget {
  const _UnsupportedNode({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Padding(padding: const EdgeInsets.all(10), child: Text(label)),
      );
}
