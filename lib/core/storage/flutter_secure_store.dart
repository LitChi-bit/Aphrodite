import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/app_exception.dart';
import 'secure_store.dart';

final class FlutterSecureStore implements SecureStore {
  FlutterSecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object catch (error) {
      throw StorageException('删除安全数据失败', cause: error);
    }
  }

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object catch (error) {
      throw StorageException('读取安全数据失败', cause: error);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Object catch (error) {
      throw StorageException('保存安全数据失败', cause: error);
    }
  }
}
