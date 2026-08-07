import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:aphrodite/chat/e2ee/native_openmls_session.dart';
import 'package:aphrodite/chat/e2ee/openmls_ffi_bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps public identity and key package JSON then releases every buffer',
      () async {
    final native = _FakeNativeOpenMlsApi();
    final session = NativeOpenMlsSession(
      bindings: native,
      appSupportDir: r'C:\Aphrodite\state',
    )..open();

    final identity = await session.initializeDevice(deviceId: 'device-1');
    final packages = await session.generateKeyPackages(
      count: 1,
      expiresAt: DateTime.utc(2026, 8, 3, 17),
    );

    expect(identity.deviceId, 'device-1');
    expect(identity.publicIdentity, <int>[1, 2]);
    expect(packages, hasLength(1));
    expect(packages.single.keyPackage, <int>[10, 11]);
    expect(packages.single.signature, <int>[12]);
    expect(packages.single.expiresAt, DateTime.utc(2026, 8, 3, 17));
    expect(native.releasedBuffers, 2);

    await session.close();
    expect(native.closed, isTrue);
  });

  test('releases an error response buffer before surfacing native failure',
      () async {
    final native = _FakeNativeOpenMlsApi(failInitialization: true);
    final session = NativeOpenMlsSession(
      bindings: native,
      appSupportDir: r'C:\Aphrodite\state',
    )..open();

    await expectLater(
      session.initializeDevice(deviceId: 'device-1'),
      throwsA(isA<NativeOpenMlsException>()),
    );
    expect(native.releasedBuffers, 1);
  });
}

final class _FakeNativeOpenMlsApi implements NativeOpenMlsApi {
  _FakeNativeOpenMlsApi({this.failInitialization = false});

  final bool failInitialization;
  var closed = false;
  var releasedBuffers = 0;
  final _buffers = <ffi.Pointer<AphroditeOpenMlsBuffer>>[];

  @override
  ffi.Pointer<ffi.Void> open(String appSupportDir) =>
      calloc<ffi.Uint8>().cast();

  @override
  AphroditeOpenMlsBuffer initializeDevice(
    ffi.Pointer<ffi.Void> handle,
    String deviceId,
  ) =>
      _jsonBuffer(
        failInitialization
            ? <String, dynamic>{
                'abi_version': 1,
                'ok': false,
                'data': null,
                'error': <String, dynamic>{'message': 'invalid device'},
              }
            : <String, dynamic>{
                'abi_version': 1,
                'ok': true,
                'data': <String, dynamic>{
                  'device_id': deviceId,
                  'credential_identity': '0102',
                  'signature_public_key': '0304',
                },
                'error': null,
              },
      );

  @override
  AphroditeOpenMlsBuffer generateKeyPackages(
    ffi.Pointer<ffi.Void> handle,
    int count,
    int expiresAt,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'ciphersuite': 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
            'key_package': '0a0b',
            'signature': '0c',
            'expires_at': expiresAt,
          },
        ],
        'error': null,
      });

  @override
  void close(ffi.Pointer<ffi.Void> handle) {
    closed = true;
    calloc.free(handle);
  }

  @override
  void freeBuffer(AphroditeOpenMlsBuffer buffer) {
    releasedBuffers += 1;
    calloc.free(buffer.data);
    final pointer = _buffers.firstWhere((item) => item.ref.data == buffer.data);
    _buffers.remove(pointer);
    calloc.free(pointer);
  }

  AphroditeOpenMlsBuffer _jsonBuffer(Map<String, dynamic> response) {
    final bytes = utf8.encode(jsonEncode(response));
    final data = calloc<ffi.Uint8>(bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    final buffer = calloc<AphroditeOpenMlsBuffer>();
    buffer.ref
      ..data = data
      ..len = bytes.length;
    _buffers.add(buffer);
    return buffer.ref;
  }
}
