import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/secure_store.dart';
import 'auth_api.dart';

class SecureDeviceIdentityProvider implements DeviceIdentityProvider {
  SecureDeviceIdentityProvider({
    required SecureStore secureStore,
    required String deviceName,
    required String platform,
    Ed25519? algorithm,
    Uuid? uuid,
  })  : _secureStore = secureStore,
        _deviceName = _validateDeviceName(deviceName),
        _platform = _validatePlatform(platform),
        _algorithm = algorithm ?? Ed25519(),
        _uuid = uuid ?? const Uuid();

  static const _deviceIdKey = 'auth.device_id';
  static const _privateKeySeedKey = 'auth.identity_private_key_seed';
  static const _supportedPlatforms = {
    'android',
    'ios',
    'windows',
    'macos',
    'linux',
    'web',
  };

  final SecureStore _secureStore;
  final String _deviceName;
  final String _platform;
  final Ed25519 _algorithm;
  final Uuid _uuid;
  Future<DeviceIdentity>? _pendingIdentity;

  @override
  Future<DeviceIdentity> getOrCreate() {
    return _pendingIdentity ??= _loadOrCreate().whenComplete(() {
      _pendingIdentity = null;
    });
  }

  Future<DeviceIdentity> _loadOrCreate() async {
    final storedDeviceId = await _secureStore.read(_deviceIdKey);
    final storedSeed = await _secureStore.read(_privateKeySeedKey);
    if (storedDeviceId == null && storedSeed == null) {
      return _createIdentity();
    }
    if (storedDeviceId == null || storedSeed == null) {
      throw const DeviceIdentityException('设备身份安全数据不完整');
    }

    final deviceId = _parseDeviceId(storedDeviceId);
    final seed = _decodeSeed(storedSeed);
    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    if (publicKey.bytes.length != 32) {
      throw const DeviceIdentityException('设备身份公钥长度无效');
    }
    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: _deviceName,
      platform: _platform,
      identityPublicKeyBase64: base64Encode(publicKey.bytes),
    );
  }

  Future<DeviceIdentity> _createIdentity() async {
    final deviceId = _uuid.v4();
    final keyPair = await _algorithm.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    if (seed.length != 32 || publicKey.bytes.length != 32) {
      throw const DeviceIdentityException('生成的设备身份密钥长度无效');
    }

    await _secureStore.write(_privateKeySeedKey, base64Encode(seed));
    try {
      await _secureStore.write(_deviceIdKey, deviceId);
    } catch (writeError) {
      try {
        await _secureStore.delete(_privateKeySeedKey);
      } catch (rollbackError) {
        throw DeviceIdentityPersistenceException(
          '设备身份保存失败且无法回滚安全数据',
          writeError: writeError,
          rollbackError: rollbackError,
        );
      }
      rethrow;
    }
    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: _deviceName,
      platform: _platform,
      identityPublicKeyBase64: base64Encode(publicKey.bytes),
    );
  }

  String _parseDeviceId(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized != value ||
        !Uuid.isValidUUID(
          fromString: normalized,
          validationMode: ValidationMode.strictRFC9562,
        )) {
      throw const DeviceIdentityException('设备 ID 安全数据无效');
    }
    return normalized;
  }

  static List<int> _decodeSeed(String value) {
    try {
      final seed = base64Decode(value);
      if (seed.length != 32) {
        throw const DeviceIdentityException('设备身份私钥长度无效');
      }
      return seed;
    } on FormatException {
      throw const DeviceIdentityException('设备身份私钥编码无效');
    }
  }

  static String _validateDeviceName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.runes.length > 128 ||
        normalized.runes
            .any((character) => character < 0x20 || character == 0x7f)) {
      throw ArgumentError.value(
        value,
        'deviceName',
        'must contain 1 to 128 characters without control characters',
      );
    }
    return normalized;
  }

  static String _validatePlatform(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_supportedPlatforms.contains(normalized)) {
      throw ArgumentError.value(value, 'platform', 'is not supported');
    }
    return normalized;
  }
}

class DeviceIdentityException implements Exception {
  const DeviceIdentityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DeviceIdentityPersistenceException extends DeviceIdentityException {
  const DeviceIdentityPersistenceException(
    super.message, {
    required this.writeError,
    required this.rollbackError,
  });

  final Object writeError;
  final Object rollbackError;
}
