abstract interface class FileCrypto {
  Future<EncryptedFile> encrypt({
    required Uri source,
    required String associatedFileId,
  });

  Future<Uri> decrypt({
    required EncryptedFile encryptedFile,
    required Uri destination,
  });
}

class EncryptedFile {
  EncryptedFile({
    required this.uri,
    required List<int> key,
    required List<int> nonce,
    required List<int> sha256,
    required this.byteSize,
  })  : key = List.unmodifiable(key),
        nonce = List.unmodifiable(nonce),
        sha256 = List.unmodifiable(sha256);

  final Uri uri;
  final List<int> key;
  final List<int> nonce;
  final List<int> sha256;
  final int byteSize;
}
