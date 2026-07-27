abstract interface class E2eeClient {
  Future<EncryptedPayload> encryptMessage({
    required String conversationId,
    required List<int> plaintext,
  });

  Future<List<int>> decryptMessage({
    required String conversationId,
    required EncryptedPayload payload,
  });
}

class EncryptedPayload {
  EncryptedPayload({
    required List<int> ciphertext,
    required this.scheme,
    required this.groupId,
    required this.epoch,
    required List<int> header,
  })  : ciphertext = List.unmodifiable(ciphertext),
        header = List.unmodifiable(header);

  final List<int> ciphertext;
  final String scheme;
  final String groupId;
  final int epoch;
  final List<int> header;
}
