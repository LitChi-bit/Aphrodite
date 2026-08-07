import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

final class AphroditeOpenMlsBuffer extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> data;

  @ffi.UintPtr()
  external int len;
}

abstract interface class NativeOpenMlsApi {
  ffi.Pointer<ffi.Void> open(String appSupportDir);

  AphroditeOpenMlsBuffer initializeDevice(
    ffi.Pointer<ffi.Void> handle,
    String deviceId,
  );

  AphroditeOpenMlsBuffer generateKeyPackages(
    ffi.Pointer<ffi.Void> handle,
    int count,
    int expiresAt,
  );

  void close(ffi.Pointer<ffi.Void> handle);

  void freeBuffer(AphroditeOpenMlsBuffer buffer);
}

final class NativeOpenMlsBindings implements NativeOpenMlsApi {
  NativeOpenMlsBindings(ffi.DynamicLibrary library)
      : _open = library.lookupFunction<_OpenNative, _OpenDart>(
          'aphrodite_openmls_open',
        ),
        _initializeDevice =
            library.lookupFunction<_InitializeNative, _InitializeDart>(
          'aphrodite_openmls_initialize_device',
        ),
        _generateKeyPackages =
            library.lookupFunction<_GenerateNative, _GenerateDart>(
          'aphrodite_openmls_generate_key_packages',
        ),
        _close = library.lookupFunction<_CloseNative, _CloseDart>(
          'aphrodite_openmls_close',
        ),
        _freeBuffer =
            library.lookupFunction<_FreeBufferNative, _FreeBufferDart>(
          'aphrodite_openmls_free_buffer',
        );

  final _OpenDart _open;
  final _InitializeDart _initializeDevice;
  final _GenerateDart _generateKeyPackages;
  final _CloseDart _close;
  final _FreeBufferDart _freeBuffer;

  @override
  ffi.Pointer<ffi.Void> open(String appSupportDir) {
    final path = appSupportDir.toNativeUtf8();
    try {
      return _open(path.cast());
    } finally {
      calloc.free(path);
    }
  }

  @override
  AphroditeOpenMlsBuffer initializeDevice(
    ffi.Pointer<ffi.Void> handle,
    String deviceId,
  ) {
    final nativeDeviceId = deviceId.toNativeUtf8();
    try {
      return _initializeDevice(handle, nativeDeviceId.cast());
    } finally {
      calloc.free(nativeDeviceId);
    }
  }

  @override
  AphroditeOpenMlsBuffer generateKeyPackages(
    ffi.Pointer<ffi.Void> handle,
    int count,
    int expiresAt,
  ) =>
      _generateKeyPackages(handle, count, expiresAt);

  @override
  void close(ffi.Pointer<ffi.Void> handle) => _close(handle);

  @override
  void freeBuffer(AphroditeOpenMlsBuffer buffer) => _freeBuffer(buffer);
}

typedef _OpenNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>);
typedef _OpenDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>);

typedef _InitializeNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);
typedef _InitializeDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);

typedef _GenerateNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint32,
  ffi.Uint64,
);
typedef _GenerateDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
);

typedef _CloseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _CloseDart = void Function(ffi.Pointer<ffi.Void>);

typedef _FreeBufferNative = ffi.Void Function(AphroditeOpenMlsBuffer);
typedef _FreeBufferDart = void Function(AphroditeOpenMlsBuffer);
