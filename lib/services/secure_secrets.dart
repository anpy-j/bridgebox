import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 口令与私钥只进安全存储，不进 SharedPreferences、不进仓库。
class SecureSecrets {
  SecureSecrets({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  Future<void> savePassword(String hostId, String password) {
    return _storage.write(key: 'pwd.$hostId', value: password);
  }

  Future<void> savePrivateKey({
    required String hostId,
    required String pem,
    String? passphrase,
  }) async {
    await _storage.write(key: 'key.$hostId', value: pem);
    if (passphrase != null && passphrase.isNotEmpty) {
      await _storage.write(key: 'keypass.$hostId', value: passphrase);
    } else {
      await _storage.delete(key: 'keypass.$hostId');
    }
  }

  Future<String?> password(String hostId) => _storage.read(key: 'pwd.$hostId');

  Future<String?> privateKey(String hostId) => _storage.read(key: 'key.$hostId');

  Future<String?> keyPassphrase(String hostId) =>
      _storage.read(key: 'keypass.$hostId');

  Future<void> deleteHost(String hostId) async {
    await _storage.delete(key: 'pwd.$hostId');
    await _storage.delete(key: 'key.$hostId');
    await _storage.delete(key: 'keypass.$hostId');
  }
}
