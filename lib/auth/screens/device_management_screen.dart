import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/dto/device_dto.dart';
import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';

class DeviceManagementScreen extends ConsumerStatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  ConsumerState<DeviceManagementScreen> createState() =>
      _DeviceManagementScreenState();
}

class _DeviceManagementScreenState
    extends ConsumerState<DeviceManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_usesDemoAuthentication) return;
      ref.read(deviceProvider.notifier).load();
    });
  }

  bool get _usesDemoAuthentication =>
      ref.read(authRepositoryProvider) is DemoAuthRepository;

  @override
  Widget build(BuildContext context) {
    if (_usesDemoAuthentication) {
      return Scaffold(
        appBar: AppBar(title: const Text('设备管理')),
        body: const _UnavailableState(),
      );
    }

    final state = ref.watch(deviceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备管理'),
        actions: [
          IconButton(
            tooltip: '刷新设备列表',
            onPressed: state.isLoading
                ? null
                : () => ref.read(deviceProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (state.status) {
        DeviceListStatus.idle ||
        DeviceListStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        DeviceListStatus.error => _DeviceLoadError(
            message: state.errorMessage ?? '设备列表加载失败',
            onRetry: () => ref.read(deviceProvider.notifier).load(),
          ),
        DeviceListStatus.ready when state.devices.isEmpty =>
          const _EmptyDeviceState(),
        DeviceListStatus.ready => _DeviceList(
            devices: state.devices,
            mutatingDeviceId: state.mutatingDeviceId,
            errorMessage: state.errorMessage,
            onRevoke: _confirmRevoke,
          ),
      },
    );
  }

  Future<void> _confirmRevoke(DeviceDto device) async {
    if (device.current || device.revoked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            device.current ? '当前设备不能在此处撤销，请使用退出登录。' : '该设备已撤销。',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销设备'),
        content: Text('撤销“${device.name}”后，该设备将无法继续访问账号。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final revoked = await ref.read(deviceProvider.notifier).revoke(device.id);
    if (!mounted || revoked) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ref.read(deviceProvider).errorMessage ?? '撤销设备失败'),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.devices,
    required this.mutatingDeviceId,
    required this.errorMessage,
    required this.onRevoke,
  });

  final List<DeviceDto> devices;
  final String? mutatingDeviceId;
  final String? errorMessage;
  final ValueChanged<DeviceDto> onRevoke;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: devices.length + (errorMessage == null ? 0 : 1),
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          if (index == 0 && errorMessage != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          final offset = errorMessage == null ? 0 : 1;
          final device = devices[index - offset];
          final isMutating = mutatingDeviceId == device.id;
          return ListTile(
            leading: Icon(_platformIcon(device.platform)),
            title: Text(device.name),
            subtitle: Text(_subtitle(device)),
            trailing: device.current
                ? const Chip(label: Text('当前设备'))
                : device.revoked
                    ? const Chip(label: Text('已撤销'))
                    : isMutating
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: '撤销设备',
                            onPressed: () => onRevoke(device),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
          );
        },
      );

  String _subtitle(DeviceDto device) {
    if (device.revoked) return '已撤销';
    final lastSeen = device.lastSeenAt;
    if (lastSeen == null) return device.platform;
    return '${device.platform} · 最近活动 ${lastSeen.toLocal()}';
  }

  IconData _platformIcon(String platform) => switch (platform) {
        'android' => Icons.android,
        'ios' || 'macos' => Icons.apple,
        'windows' => Icons.window,
        'linux' => Icons.terminal,
        'web' => Icons.language,
        _ => Icons.devices_other,
      };
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.devices_outlined, size: 52),
              SizedBox(height: 16),
              Text('使用真实账号登录后可管理设备'),
            ],
          ),
        ),
      );
}

class _EmptyDeviceState extends StatelessWidget {
  const _EmptyDeviceState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Text('没有可管理的设备'),
      );
}

class _DeviceLoadError extends StatelessWidget {
  const _DeviceLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
}
