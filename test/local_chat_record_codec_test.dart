import 'dart:convert';
import 'dart:typed_data';

import 'package:aphrodite/chat/data/local_chat_record_codec.dart';
import 'package:aphrodite/core/storage/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seals records with a stable secure-store key and random nonces',
      () async {
    final store = _MemorySecureStore();
    final codec = LocalChatRecordCodec(secureStore: store);
    const record = {'text': 'Local-only plaintext', 'version': 1};

    final first = await codec.seal(record);
    final second = await codec.seal(record);
    final restored = await codec.open(first);

    expect(first, isNot(second));
    expect(utf8.decode(first, allowMalformed: true),
        isNot(contains('Local-only plaintext')));
    expect(restored, record);
    expect(store.values, contains('chat.local_record_key.v1'));

    final reloaded = LocalChatRecordCodec(secureStore: store);
    expect(await reloaded.open(second), record);
  });

  test('rejects tampered records without returning plaintext', () async {
    final codec = LocalChatRecordCodec(secureStore: _MemorySecureStore());
    final sealed = await codec.seal(const {'text': 'Local-only plaintext'});
    final tampered = Uint8List.fromList(sealed);
    tampered[12] ^= 1;

    expect(
      () => codec.open(tampered),
      throwsA(isA<ChatRecordCodecException>()),
    );
  });

  test('rejects malformed persisted keys', () async {
    final codec = LocalChatRecordCodec(
      secureStore: _MemorySecureStore(
        values: {
          'chat.local_record_key.v1': base64Encode(const [1, 2])
        },
      ),
    );

    expect(
      () => codec.seal(const {'text': 'Local-only plaintext'}),
      throwsA(isA<ChatRecordCodecException>()),
    );
  });
}

class _MemorySecureStore implements SecureStore {
  _MemorySecureStore({Map<String, String>? values})
      : values = <String, String>{...?values};

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
