import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/storage/secure_store.dart';
import 'drift_chat_database.dart';

class LocalChatRecordCodec implements ChatRecordCodec {
  LocalChatRecordCodec({
    required SecureStore secureStore,
    Cipher? cipher,
    Random? random,
  })  : _secureStore = secureStore,
        _cipher = cipher ?? AesGcm.with256bits(),
        _random = random ?? Random.secure();

  static const _keyStorageKey = 'chat.local_record_key.v1';
  static const _nonceLength = 12;

  final SecureStore _secureStore;
  final Cipher _cipher;
  final Random _random;
  SecretKey? _cachedKey;
  Future<SecretKey>? _pendingKey;

  @override
  Future<Uint8List> seal(Map<String, dynamic> record) async {
    final plaintext = utf8.encode(jsonEncode(record));
    final nonce = List<int>.generate(_nonceLength, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: await _key(),
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  @override
  Future<Map<String, dynamic>> open(Uint8List sealedRecord) async {
    final macLength = _cipher.macAlgorithm.macLength;
    if (sealedRecord.length <= _nonceLength + macLength) {
      throw const ChatRecordCodecException('sealed record is malformed');
    }
    final nonce = sealedRecord.sublist(0, _nonceLength);
    final ciphertext = sealedRecord.sublist(
      _nonceLength,
      sealedRecord.length - macLength,
    );
    final mac = Mac(sealedRecord.sublist(sealedRecord.length - macLength));
    try {
      final plaintext = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: mac),
        secretKey: await _key(),
      );
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, dynamic>) {
        throw const ChatRecordCodecException('sealed record has invalid JSON');
      }
      return decoded;
    } on SecretBoxAuthenticationError {
      throw const ChatRecordCodecException(
          'sealed record authentication failed');
    } on FormatException {
      throw const ChatRecordCodecException('sealed record has invalid JSON');
    }
  }

  Future<SecretKey> _key() {
    final cached = _cachedKey;
    if (cached != null) return Future.value(cached);
    return _pendingKey ??= _loadOrCreateKey();
  }

  Future<SecretKey> _loadOrCreateKey() async {
    try {
      final stored = await _secureStore.read(_keyStorageKey);
      final bytes = stored == null ? null : base64Decode(stored);
      if (bytes != null) {
        if (bytes.length != 32) {
          throw const ChatRecordCodecException(
              'stored local chat key is invalid');
        }
        return _cachedKey = SecretKey(bytes);
      }
      final generated = List<int>.generate(32, (_) => _random.nextInt(256));
      await _secureStore.write(_keyStorageKey, base64Encode(generated));
      return _cachedKey = SecretKey(generated);
    } on FormatException {
      throw const ChatRecordCodecException('stored local chat key is invalid');
    } finally {
      _pendingKey = null;
    }
  }
}

class ChatRecordCodecException implements Exception {
  const ChatRecordCodecException(this.message);

  final String message;

  @override
  String toString() => 'ChatRecordCodecException: $message';
}
