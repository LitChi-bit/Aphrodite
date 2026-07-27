abstract interface class CallMediaCrypto {
  Future<void> enable({
    required String callId,
    required List<int> mediaKey,
  });

  Future<void> rotateKey(List<int> mediaKey);

  Future<void> disable();
}
