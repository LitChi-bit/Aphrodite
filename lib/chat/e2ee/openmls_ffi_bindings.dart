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

  AphroditeOpenMlsBuffer createGroup(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
  );

  AphroditeOpenMlsBuffer addMember(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> keyPackage,
  );

  AphroditeOpenMlsBuffer joinGroup(
    ffi.Pointer<ffi.Void> handle,
    List<int> welcome,
  );

  AphroditeOpenMlsBuffer encryptApplicationMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> plaintext,
  );

  AphroditeOpenMlsBuffer decryptApplicationMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> ciphertext,
  );

  AphroditeOpenMlsBuffer applyHandshakeMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> handshake,
  );

  AphroditeOpenMlsBuffer commitPendingProposals(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
  );

  AphroditeOpenMlsBuffer removeLocalGroup(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
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
        _createGroup =
            library.lookupFunction<_CreateGroupNative, _CreateGroupDart>(
          'aphrodite_openmls_create_group',
        ),
        _addMember = library.lookupFunction<_AddMemberNative, _AddMemberDart>(
          'aphrodite_openmls_add_member',
        ),
        _joinGroup = library.lookupFunction<_JoinGroupNative, _JoinGroupDart>(
          'aphrodite_openmls_join_group',
        ),
        _encryptApplicationMessage = library.lookupFunction<
            _EncryptApplicationMessageNative, _EncryptApplicationMessageDart>(
          'aphrodite_openmls_encrypt_application_message',
        ),
        _decryptApplicationMessage = library.lookupFunction<
            _DecryptApplicationMessageNative, _DecryptApplicationMessageDart>(
          'aphrodite_openmls_decrypt_application_message',
        ),
        _applyHandshakeMessage = library.lookupFunction<
            _ApplyHandshakeMessageNative, _ApplyHandshakeMessageDart>(
          'aphrodite_openmls_apply_handshake_message',
        ),
        _commitPendingProposals = library.lookupFunction<
            _CommitPendingProposalsNative, _CommitPendingProposalsDart>(
          'aphrodite_openmls_commit_pending_proposals',
        ),
        _removeLocalGroup = library
            .lookupFunction<_RemoveLocalGroupNative, _RemoveLocalGroupDart>(
          'aphrodite_openmls_remove_local_group',
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
  final _CreateGroupDart _createGroup;
  final _AddMemberDart _addMember;
  final _JoinGroupDart _joinGroup;
  final _EncryptApplicationMessageDart _encryptApplicationMessage;
  final _DecryptApplicationMessageDart _decryptApplicationMessage;
  final _ApplyHandshakeMessageDart _applyHandshakeMessage;
  final _CommitPendingProposalsDart _commitPendingProposals;
  final _RemoveLocalGroupDart _removeLocalGroup;
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
  AphroditeOpenMlsBuffer createGroup(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
  ) {
    final id = conversationId.toNativeUtf8();
    try {
      return _createGroup(handle, id.cast());
    } finally {
      calloc.free(id);
    }
  }

  @override
  AphroditeOpenMlsBuffer addMember(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> keyPackage,
  ) {
    final id = conversationId.toNativeUtf8();
    final bytes = calloc<ffi.Uint8>(keyPackage.length);
    bytes.asTypedList(keyPackage.length).setAll(0, keyPackage);
    try {
      return _addMember(handle, id.cast(), bytes, keyPackage.length);
    } finally {
      calloc.free(id);
      calloc.free(bytes);
    }
  }

  @override
  AphroditeOpenMlsBuffer joinGroup(
    ffi.Pointer<ffi.Void> handle,
    List<int> welcome,
  ) {
    final bytes = calloc<ffi.Uint8>(welcome.length);
    bytes.asTypedList(welcome.length).setAll(0, welcome);
    try {
      return _joinGroup(handle, bytes, welcome.length);
    } finally {
      calloc.free(bytes);
    }
  }

  @override
  AphroditeOpenMlsBuffer encryptApplicationMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> plaintext,
  ) =>
      _withBinaryText(
        conversationId,
        plaintext,
        (id, bytes) => _encryptApplicationMessage(
          handle,
          id,
          bytes,
          plaintext.length,
        ),
      );

  @override
  AphroditeOpenMlsBuffer decryptApplicationMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> ciphertext,
  ) =>
      _withBinaryText(
        conversationId,
        ciphertext,
        (id, bytes) => _decryptApplicationMessage(
          handle,
          id,
          bytes,
          ciphertext.length,
        ),
      );

  AphroditeOpenMlsBuffer _withBinaryText(
    String conversationId,
    List<int> bytes,
    AphroditeOpenMlsBuffer Function(
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Uint8>,
    ) callback,
  ) {
    final id = conversationId.toNativeUtf8();
    final data = calloc<ffi.Uint8>(bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    try {
      return callback(id.cast(), data);
    } finally {
      calloc.free(id);
      calloc.free(data);
    }
  }

  @override
  AphroditeOpenMlsBuffer applyHandshakeMessage(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
    List<int> handshake,
  ) =>
      _withBinaryText(
        conversationId,
        handshake,
        (id, bytes) => _applyHandshakeMessage(
          handle,
          id,
          bytes,
          handshake.length,
        ),
      );

  @override
  AphroditeOpenMlsBuffer commitPendingProposals(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
  ) {
    final id = conversationId.toNativeUtf8();
    try {
      return _commitPendingProposals(handle, id.cast());
    } finally {
      calloc.free(id);
    }
  }

  @override
  AphroditeOpenMlsBuffer removeLocalGroup(
    ffi.Pointer<ffi.Void> handle,
    String conversationId,
  ) {
    final id = conversationId.toNativeUtf8();
    try {
      return _removeLocalGroup(handle, id.cast());
    } finally {
      calloc.free(id);
    }
  }

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

typedef _CreateGroupNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);
typedef _CreateGroupDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);

typedef _AddMemberNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint8>,
  ffi.UintPtr,
);
typedef _AddMemberDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _JoinGroupNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  ffi.UintPtr,
);
typedef _JoinGroupDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _EncryptApplicationMessageNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint8>,
  ffi.UintPtr,
);
typedef _EncryptApplicationMessageDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _DecryptApplicationMessageNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint8>,
  ffi.UintPtr,
);
typedef _DecryptApplicationMessageDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _ApplyHandshakeMessageNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint8>,
  ffi.UintPtr,
);
typedef _ApplyHandshakeMessageDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Uint8>,
  int,
);

typedef _CommitPendingProposalsNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);
typedef _CommitPendingProposalsDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);

typedef _RemoveLocalGroupNative = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);
typedef _RemoveLocalGroupDart = AphroditeOpenMlsBuffer Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);

typedef _CloseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _CloseDart = void Function(ffi.Pointer<ffi.Void>);

typedef _FreeBufferNative = ffi.Void Function(AphroditeOpenMlsBuffer);
typedef _FreeBufferDart = void Function(AphroditeOpenMlsBuffer);
