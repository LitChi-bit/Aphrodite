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
    final groupId = await session.createGroup(
      conversationId: 'conversation-1',
    );
    final welcome = await session.addMember(
      conversationId: 'conversation-1',
      keyPackage: <int>[9, 10],
    );
    final joined = await session.joinGroup(welcome: welcome.welcome);
    final encrypted = await session.encryptApplicationMessage(
      conversationId: 'conversation-1',
      plaintext: <int>[98, 105, 110, 97, 114, 121, 0],
    );
    final payload = await session.encryptMessage(
      conversationId: 'conversation-1',
      plaintext: <int>[98, 105, 110, 97, 114, 121, 0],
    );
    final plaintext = await session.decryptApplicationMessage(
      conversationId: 'conversation-1',
      ciphertext: encrypted.ciphertext,
    );
    final handshake = await session.applyHandshakeMessage(
      conversationId: 'conversation-1',
      handshake: <int>[13, 14],
    );
    final commit = await session.commitPendingProposals(
      conversationId: 'conversation-1',
    );

    expect(groupId, 'conversation-1'.codeUnits);
    expect(welcome.commit, <int>[3, 4]);
    expect(welcome.welcome, <int>[5, 6]);
    expect(welcome.groupInfo, isNull);
    expect(joined, 'conversation-1'.codeUnits);
    expect(encrypted.ciphertext, <int>[7, 8]);
    expect(encrypted.scheme, nativeOpenMlsCiphersuite);
    expect(encrypted.groupId, 'conversation-1'.codeUnits);
    expect(encrypted.epoch, 3);
    expect(encrypted.header, isEmpty);
    expect(payload.ciphertext, <int>[7, 8]);
    expect(payload.scheme, nativeOpenMlsCiphersuite);
    expect(payload.groupId, 'conversation-1');
    expect(payload.epoch, 3);
    expect(payload.header, isEmpty);
    expect(plaintext, <int>[98, 105, 110, 97, 114, 121, 0]);
    expect(handshake.kind, 'proposal_stored');
    expect(handshake.epoch, 1);
    expect(commit.commit, <int>[15, 16]);
    expect(commit.welcome, isNull);
    expect(commit.groupInfo, <int>[17]);
    expect(commit.epoch, 2);
    await session.removeLocalGroup(conversationId: 'conversation-1');
    await session.destroyDeviceState();
    expect(native.releasedBuffers, 12);

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
  AphroditeOpenMlsBuffer createGroup(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{
          'group_id': '636f6e766572736174696f6e2d31',
        },
        'error': null,
      });

  @override
  AphroditeOpenMlsBuffer addMember(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> keyPackage,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{
          'commit': '0304',
          'welcome': '0506',
          'group_info': null,
        },
        'error': null,
      });

  @override
  AphroditeOpenMlsBuffer joinGroup(
    ffi.Pointer<ffi.Void> handle,
    List<int> welcome,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{
          'group_id': '636f6e766572736174696f6e2d31',
        },
        'error': null,
      });

  @override
  AphroditeOpenMlsBuffer encryptApplicationMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> plaintext,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{
          'ciphertext': '0708',
          'scheme': nativeOpenMlsCiphersuite,
          'group_id': '636f6e766572736174696f6e2d31',
          'epoch': 3,
          'header': '',
        },
        'error': null,
      });

  @override
  AphroditeOpenMlsBuffer decryptApplicationMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> ciphertext,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{'plaintext': '62696e61727900'},
        'error': null,
      });

  @override
  AphroditeOpenMlsBuffer applyHandshakeMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> handshake,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{'kind': 'proposal_stored', 'epoch': 1},
        'error': null,
      });

  @override
  AphroditeOpenMlsBuffer commitPendingProposals(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{
          'commit': '0f10',
          'welcome': null,
          'group_info': '11',
          'epoch': 2,
        },
        'error': null,
      });

  @override
  AphroditeOpenMlsBuffer removeLocalGroup(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{},
        'error': null,
      });

  @override
  AphroditeOpenMlsBuffer destroyDeviceState(
    ffi.Pointer<ffi.Void> handle,
  ) =>
      _jsonBuffer(<String, dynamic>{
        'abi_version': 1,
        'ok': true,
        'data': <String, dynamic>{},
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
