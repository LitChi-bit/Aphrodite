import '../../core/network/network_client.dart';
import 'dto/device_dto.dart';

class DeviceApi {
  const DeviceApi({required NetworkClient networkClient})
      : _networkClient = networkClient;

  final NetworkClient _networkClient;

  Future<List<DeviceDto>> listDevices() async {
    final response = await _networkClient.get('/v1/devices');
    return parseDeviceListResponse(response);
  }

  Future<void> revokeDevice(String deviceId) async {
    final normalizedId = deviceId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Device ID is required.');
    }
    await _networkClient.delete('/v1/devices/$normalizedId');
  }
}
