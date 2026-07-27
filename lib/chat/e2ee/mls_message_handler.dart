import 'e2ee_client.dart';

class MlsMessageHandler {
  const MlsMessageHandler({required E2eeClient client}) : _client = client;

  final E2eeClient _client;

  Future<EncryptedPayload> encrypt({
    required String conversationId,
    required List<int> plaintext,
  }) {
    return _client.encryptMessage(
      conversationId: conversationId,
      plaintext: plaintext,
    );
  }

  Future<List<int>> decrypt({
    required String conversationId,
    required EncryptedPayload payload,
  }) {
    return _client.decryptMessage(
      conversationId: conversationId,
      payload: payload,
    );
  }
}
