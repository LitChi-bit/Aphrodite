import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scope.dart';
import '../data/device_api.dart';
import '../data/dto/device_dto.dart';

enum DeviceListStatus { idle, loading, ready, error }

class DeviceState {
  const DeviceState({
    this.status = DeviceListStatus.idle,
    this.devices = const <DeviceDto>[],
    this.errorMessage,
    this.mutatingDeviceId,
  });

  final DeviceListStatus status;
  final List<DeviceDto> devices;
  final String? errorMessage;
  final String? mutatingDeviceId;

  bool get isLoading => status == DeviceListStatus.loading;
  bool get isMutating => mutatingDeviceId != null;

  DeviceState copyWith({
    DeviceListStatus? status,
    List<DeviceDto>? devices,
    String? errorMessage,
    bool clearError = false,
    String? mutatingDeviceId,
    bool clearMutatingDeviceId = false,
  }) {
    return DeviceState(
      status: status ?? this.status,
      devices: devices ?? this.devices,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      mutatingDeviceId: clearMutatingDeviceId
          ? null
          : mutatingDeviceId ?? this.mutatingDeviceId,
    );
  }
}

final deviceProvider =
    StateNotifierProvider.autoDispose<DeviceNotifier, DeviceState>((ref) {
  return DeviceNotifier(api: ref.watch(deviceApiProvider));
});

class DeviceNotifier extends StateNotifier<DeviceState> {
  DeviceNotifier({required this.api}) : super(const DeviceState());

  final DeviceApi api;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(
      status: DeviceListStatus.loading,
      clearError: true,
    );
    try {
      final devices = await api.listDevices();
      if (!mounted) return;
      state = state.copyWith(
        status: DeviceListStatus.ready,
        devices: List<DeviceDto>.unmodifiable(devices),
        clearError: true,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        status: DeviceListStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  Future<bool> revoke(String deviceId) async {
    final normalizedId = deviceId.trim();
    if (normalizedId.isEmpty || state.isMutating) return false;
    state = state.copyWith(
      mutatingDeviceId: normalizedId,
      clearError: true,
    );
    try {
      await api.revokeDevice(normalizedId);
      if (!mounted) return false;
      state = state.copyWith(
        status: DeviceListStatus.ready,
        devices: state.devices
            .where((device) => device.id != normalizedId)
            .toList(growable: false),
        clearMutatingDeviceId: true,
        clearError: true,
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        errorMessage: error.toString(),
        clearMutatingDeviceId: true,
      );
      return false;
    }
  }
}
