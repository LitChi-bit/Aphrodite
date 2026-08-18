import 'dart:ffi' as ffi;
import 'dart:io';

import 'openmls_ffi_bindings.dart';

const nativeOpenMlsLibraryName = 'aphrodite_openmls';

ffi.DynamicLibrary openNativeOpenMlsLibrary() {
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('$nativeOpenMlsLibraryName.dll');
  }
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('lib$nativeOpenMlsLibraryName.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return ffi.DynamicLibrary.process();
  }
  if (Platform.isLinux) {
    return ffi.DynamicLibrary.open('lib$nativeOpenMlsLibraryName.so');
  }
  throw UnsupportedError('native OpenMLS is unsupported on this platform');
}

NativeOpenMlsBindings loadNativeOpenMlsBindings() =>
    NativeOpenMlsBindings(openNativeOpenMlsLibrary());

String validateNativeOpenMlsSupportDirectory(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty || !File(normalized).isAbsolute) {
    throw ArgumentError.value(
      path,
      'path',
      'must be a non-empty absolute path',
    );
  }
  return normalized;
}
