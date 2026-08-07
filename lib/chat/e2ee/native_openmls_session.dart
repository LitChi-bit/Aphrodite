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
