import 'dart:async';

import 'package:aphrodite/auth/data/device_api.dart';
import 'package:aphrodite/auth/data/dto/device_dto.dart';
import 'package:aphrodite/auth/providers/device_provider.dart';
import 'package:aphrodite/core/network/network_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads devices into a ready state', () async {
    final api = _FakeDeviceApi(devices: [_device('device-1')]);
    final notifier = DeviceNotifier(api: api);
    addTearDown(notifier.dispose);

    expect(notifier.state.status, DeviceListStatus.idle);
    await notifier.load();

    expect(notifier.state.status, DeviceListStatus.ready);
    expect(notifier.state.devices.single.id, 'device-1');
    expect(api.listCalls, 1);
  });

  test('load failure preserves an empty list and exposes an error', () async {
    final notifier = DeviceNotifier(
      api: _FakeDeviceApi(loadError: StateError('load failed')),
    );
    addTearDown(notifier.dispose);

    await notifier.load();

    expect(notifier.state.status, DeviceListStatus.error);
    expect(notifier.state.devices, isEmpty);
    expect(notifier.state.errorMessage, contains('load failed'));
  });

  test('successful revoke removes the device locally', () async {
    final api = _FakeDeviceApi(
      devices: [_device('device-1'), _device('device-2')],
    );
    final notifier = DeviceNotifier(api: api);
    addTearDown(notifier.dispose);
    await notifier.load();

    expect(await notifier.revoke(' device-1 '), isTrue);

    expect(api.revokedIds, ['device-1']);
    expect(notifier.state.devices.map((device) => device.id), ['device-2']);
    expect(notifier.state.mutatingDeviceId, isNull);
  });

  test('failed revoke keeps the device and clears mutation state', () async {
    final notifier = DeviceNotifier(
      api: _FakeDeviceApi(
        devices: [_device('device-1')],
        revokeError: StateError('revoke failed'),
      ),
    );
    addTearDown(notifier.dispose);
    await notifier.load();

    expect(await notifier.revoke('device-1'), isFalse);

    expect(notifier.state.devices.single.id, 'device-1');
    expect(notifier.state.mutatingDeviceId, isNull);
    expect(notifier.state.errorMessage, contains('revoke failed'));
  });

  test('does not start a second mutation while one is active', () async {
    final api = _FakeDeviceApi(
      devices: [_device('device-1'), _device('device-2')],
      holdRevoke: true,
    );
    final notifier = DeviceNotifier(api: api);
    addTearDown(notifier.dispose);
    await notifier.load();

    final first = notifier.revoke('device-1');
    expect(await notifier.revoke('device-2'), isFalse);
    expect(api.revokedIds, isEmpty);

    api.completeRevoke();
    expect(await first, isTrue);
    expect(api.revokedIds, ['device-1']);
  });

  test('ignores a pre-revocation device load that completes late', () async {
    final api = _FakeDeviceApi(
      devices: [_device('device-1'), _device('device-2')],
    );
    final notifier = DeviceNotifier(api: api);
    addTearDown(notifier.dispose);
    await notifier.load();

    api.holdNextLoad();
    final loading = notifier.load();
    final revoke = notifier.revoke('device-2');
    await revoke;
    api.completeLoad();
    await loading;

    expect(notifier.state.devices.map((device) => device.id), ['device-1']);
  });

  test('does not revoke an already revoked device', () async {
    final api = _FakeDeviceApi(devices: [_device('device-1', revoked: true)]);
    final notifier = DeviceNotifier(api: api);
    addTearDown(notifier.dispose);
    await notifier.load();

    expect(await notifier.revoke('device-1'), isFalse);
    expect(api.revokedIds, isEmpty);
  });
}

DeviceDto _device(String id, {bool revoked = false}) => DeviceDto(
      id: id,
      name: 'Aphrodite Android',
      platform: 'android',
      current: id == 'device-1',
      revoked: revoked,
      lastSeenAt: DateTime.utc(2026, 7, 31),
      createdAt: DateTime.utc(2026, 7, 1),
    );

class _FakeDeviceApi extends DeviceApi {
  _FakeDeviceApi({
    this.devices = const <DeviceDto>[],
    this.loadError,
    this.revokeError,
    this.holdRevoke = false,
  }) : super(networkClient: _NoopNetworkClient());

  final List<DeviceDto> devices;
  final Object? loadError;
  final Object? revokeError;
  final bool holdRevoke;
  final List<String> revokedIds = [];
  int listCalls = 0;
  Completer<void>? _revokeCompleter;
  Completer<List<DeviceDto>>? _loadCompleter;

  @override
  Future<List<DeviceDto>> listDevices() async {
    listCalls += 1;
    if (_loadCompleter != null) return _loadCompleter!.future;
    if (loadError != null) throw loadError!;
    return devices;
  }

  @override
  Future<void> revokeDevice(String deviceId) async {
    if (holdRevoke) {
      _revokeCompleter = Completer<void>();
      await _revokeCompleter!.future;
    }
    if (revokeError != null) throw revokeError!;
    revokedIds.add(deviceId);
  }

  void completeRevoke() => _revokeCompleter?.complete();

  void holdNextLoad() => _loadCompleter = Completer<List<DeviceDto>>();

  void completeLoad() {
    final completer = _loadCompleter;
    _loadCompleter = null;
    completer?.complete(devices);
  }
}

class _NoopNetworkClient implements NetworkClient {
  @override
  Future<Object?> delete(String path,
          {Map<String, Object?>? queryParameters}) =>
      throw UnimplementedError();

  @override
  Future<Object?> get(String path, {Map<String, Object?>? queryParameters}) =>
      throw UnimplementedError();

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) =>
      throw UnimplementedError();

  @override
  Future<Object?> put(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) =>
      throw UnimplementedError();
}
