abstract interface class MlsIdentityManager {
  Future<bool> hasIdentity(String deviceId);

  Future<MlsPublicIdentity> createIdentity(String deviceId);

  Future<void> removeIdentity(String deviceId);
}

class MlsPublicIdentity {
  MlsPublicIdentity({
    required this.deviceId,
    required List<int> publicKey,
    required List<int> keyPackage,
  })  : publicKey = List.unmodifiable(publicKey),
        keyPackage = List.unmodifiable(keyPackage);

  final String deviceId;
  final List<int> publicKey;
  final List<int> keyPackage;
}
