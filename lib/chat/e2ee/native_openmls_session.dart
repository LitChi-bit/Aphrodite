import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'openmls_client.dart';
import 'openmls_ffi_bindings.dart';

/// Minimal Dart adapter for the currently exported native OpenMLS ABI.
///
/// Group and message operations remain unavailable until their native ABI
/// functions are implemented. This class deliberately does not implement
/// [OpenMlsClient] to avoid presenting a partial MLS implementation as complete.
final class NativeOpenMlsSession {
  NativeOpenMlsSession({
    required NativeOpenMlsApi bindings,
    required String appSupportDir,
  })  : _bindings = bindings,
        _appSupportDir = _requireAbsolutePath(appSupportDir);

  final NativeOpenMlsApi _bindings;
  final String _appSupportDir;
  ffi.Pointer<ffi.Void>? _handle;
  Future<void> _operation = Future<void>.value();

  bool get isOpen => _handle != null;

  Future<OpenMlsDeviceIdentity> initializeDevice({
    required String deviceId,
  }) =>
      _serialized(() {
        final handle = _requireHandle();
        final buffer = _bindings.initializeDevice(handle, deviceId);
        final response = _readAndRelease(buffer);
        final data = _requireData(response, 'initialize_device');
        return OpenMlsDeviceIdentity(
          deviceId: _requireString(data, 'device_id'),
          publicIdentity:
              _decodeHex(_requireString(data, 'credential_identity')),
        );
      });

  Future<List<OpenMlsKeyPackage>> generateKeyPackages({
    required int count,
    required DateTime expiresAt,
  }) =>
      _serialized(() {
        if (count < 0 || count > 0xffffffff) {
          throw ArgumentError.value(count, 'count', 'must fit a uint32');
        }
        final expiresAtSeconds = expiresAt.toUtc().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond;
        if (expiresAtSeconds < 0) {
          throw ArgumentError.value(
              expiresAt, 'expiresAt', 'must be after Unix epoch');
        }
        final handle = _requireHandle();
        final buffer = _bindings.generateKeyPackages(
          handle,
          count,
          expiresAtSeconds,
        );
        final response = _readAndRelease(buffer);
        final data = _requireList(response, 'generate_key_packages');
        return data.map((item) {
          final package = _requireMap(item, 'key_package');
          return OpenMlsKeyPackage(
            ciphersuite: _requireString(package, 'ciphersuite'),
            keyPackage: _decodeHex(_requireString(package, 'key_package')),
            signature: _decodeHex(_requireString(package, 'signature')),
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _requireInt(package, 'expires_at') * 1000,
              isUtc: true,
            ),
          );
        }).toList(growable: false);
      });

  Future<List<int>> createGroup({
    required String conversationId,
  }) =>
      _serialized(() {
        final response = _readAndRelease(
          _bindings.createGroup(_requireHandle(), conversationId),
        );
        final data = _requireData(response, 'create_group');
        return _decodeHex(_requireString(data, 'group_id'));
      });

  Future<OpenMlsWelcomeBundle> addMember({
    required String conversationId,
    required List<int> keyPackage,
  }) =>
      _serialized(() {
        final response = _readAndRelease(
          _bindings.addMember(_requireHandle(), conversationId, keyPackage),
        );
        final data = _requireData(response, 'add_member');
        final groupInfo = data['group_info'];
        return OpenMlsWelcomeBundle(
          commit: _decodeHex(_requireString(data, 'commit')),
          welcome: _decodeHex(_requireString(data, 'welcome')),
          groupInfo: groupInfo == null
              ? null
              : _decodeHex(groupInfo is String ? groupInfo : ''),
        );
      });

  Future<List<int>> joinGroup({
    required List<int> welcome,
  }) =>
      _serialized(() {
        final response = _readAndRelease(
          _bindings.joinGroup(_requireHandle(), welcome),
        );
        final data = _requireData(response, 'join_group');
        return _decodeHex(_requireString(data, 'group_id'));
      });

  Future<List<int>> encryptApplicationMessage({
    required String conversationId,
    required List<int> plaintext,
  }) =>
      _serialized(() {
        final response = _readAndRelease(
          _bindings.encryptApplicationMessage(
            _requireHandle(),
            conversationId,
            plaintext,
          ),
        );
        final data = _requireData(response, 'encrypt_application_message');
        return _decodeHex(_requireString(data, 'ciphertext'));
      });

  Future<List<int>> decryptApplicationMessage({
    required String conversationId,
    required List<int> ciphertext,
  }) =>
      _serialized(() {
        final response = _readAndRelease(
          _bindings.decryptApplicationMessage(
            _requireHandle(),
            conversationId,
            ciphertext,
          ),
        );
        final data = _requireData(response, 'decrypt_application_message');
        return _decodeHex(_requireString(data, 'plaintext'));
      });

  Future<void> removeLocalGroup({
    required String conversationId,
  }) =>
      _serialized(() {
        final response = _readAndRelease(
          _bindings.removeLocalGroup(_requireHandle(), conversationId),
        );
        _requireData(response, 'remove_local_group');
      });

  Future<void> close() async {
    await _operation;
    final handle = _handle;
    if (handle != null) {
      _bindings.close(handle);
      _handle = null;
    }
  }

  void open() {
    if (isOpen) return;
    final handle = _bindings.open(_appSupportDir);
    if (handle == ffi.nullptr) {
      throw const NativeOpenMlsException(
          'native OpenMLS engine could not open');
    }
    _handle = handle;
  }

  Future<T> _serialized<T>(T Function() operation) {
    final result = _operation.then((_) => operation());
    _operation = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  ffi.Pointer<ffi.Void> _requireHandle() {
    final handle = _handle;
    if (handle == null) {
      throw const NativeOpenMlsException('native OpenMLS engine is closed');
    }
    return handle;
  }

  Map<String, dynamic> _readAndRelease(AphroditeOpenMlsBuffer buffer) {
    try {
      final bytes = buffer.data.asTypedList(buffer.len);
      final decoded = jsonDecode(utf8.decode(bytes));
      return _requireMap(decoded, 'response');
    } finally {
      _bindings.freeBuffer(buffer);
    }
  }

  Map<String, dynamic> _requireData(
      Map<String, dynamic> response, String operation) {
    _throwIfError(response, operation);
    return _requireMap(response['data'], 'data');
  }

  List<dynamic> _requireList(Map<String, dynamic> response, String operation) {
    _throwIfError(response, operation);
    final data = response['data'];
    if (data is! List) {
      throw NativeOpenMlsException('$operation returned invalid data');
    }
    return data;
  }

  void _throwIfError(Map<String, dynamic> response, String operation) {
    if (response['abi_version'] != 1) {
      throw NativeOpenMlsException(
          '$operation returned an unsupported ABI version');
    }
    if (response['ok'] == true) return;
    final error = response['error'];
    final message = error is Map ? error['message'] : null;
    throw NativeOpenMlsException(
      '$operation failed: ${message is String ? message : 'unknown native error'}',
    );
  }
}

class OpenMlsWelcomeBundle {
  OpenMlsWelcomeBundle({
    required List<int> commit,
    required List<int> welcome,
    required List<int>? groupInfo,
  })  : commit = List.unmodifiable(commit),
        welcome = List.unmodifiable(welcome),
        groupInfo = groupInfo == null ? null : List.unmodifiable(groupInfo);

  final List<int> commit;
  final List<int> welcome;
  final List<int>? groupInfo;
}

class NativeOpenMlsException implements Exception {
  const NativeOpenMlsException(this.message);
  final String message;
  @override
  String toString() => 'NativeOpenMlsException: $message';
}

String _requireAbsolutePath(String path) {
  if (path.trim().isEmpty || !File(path).isAbsolute) {
    throw ArgumentError.value(
      path,
      'appSupportDir',
      'must be an absolute path',
    );
  }
  return path;
}

Map<String, dynamic> _requireMap(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw NativeOpenMlsException('native response field $field is invalid');
}

String _requireString(Map<String, dynamic> data, String field) {
  final value = data[field];
  if (value is String) {
    return value;
  }
  throw NativeOpenMlsException('native response field $field is invalid');
}

int _requireInt(Map<String, dynamic> data, String field) {
  final value = data[field];
  if (value is int) {
    return value;
  }
  throw NativeOpenMlsException('native response field $field is invalid');
}

List<int> _decodeHex(String value) {
  if (value.length.isOdd) {
    throw const NativeOpenMlsException('native hex data is invalid');
  }
  final bytes = <int>[];
  for (var i = 0; i < value.length; i += 2) {
    final byte = int.tryParse(value.substring(i, i + 2), radix: 16);
    if (byte == null) {
      throw const NativeOpenMlsException('native hex data is invalid');
    }
    bytes.add(byte);
  }
  return List.unmodifiable(bytes);
}
