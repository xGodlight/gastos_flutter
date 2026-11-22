import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureCodec {
  SecureCodec(this._storage);

  static const _keyName = 'local_database_aes_key';
  static const _nonceLength = 12;
  static const _macLength = 16;
  final FlutterSecureStorage _storage;
  final _algorithm = AesGcm.with256bits();
  late SecretKey _key;

  Future<void> initialize() async {
    final stored = await _storage.read(key: _keyName);
    if (stored == null) {
      _key = await _algorithm.newSecretKey();
      await _storage.write(
        key: _keyName,
        value: base64Encode(await _key.extractBytes()),
      );
    } else {
      _key = SecretKey(base64Decode(stored));
    }
  }

  Future<String> encryptText(String value) async =>
      base64Encode(await encryptBytes(utf8.encode(value)));

  Future<String> decryptText(String value) async =>
      utf8.decode(await decryptBytes(base64Decode(value)));

  Future<Uint8List> encryptBytes(List<int> clearBytes) async {
    final box = await _algorithm.encrypt(clearBytes, secretKey: _key);
    return Uint8List.fromList(<int>[
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  Future<Uint8List> decryptBytes(List<int> encryptedBytes) async {
    if (encryptedBytes.length < _nonceLength + _macLength) {
      throw const FormatException('El dato cifrado está incompleto.');
    }
    final box = SecretBox(
      encryptedBytes.sublist(_nonceLength + _macLength),
      nonce: encryptedBytes.sublist(0, _nonceLength),
      mac: Mac(encryptedBytes.sublist(_nonceLength, _nonceLength + _macLength)),
    );
    return Uint8List.fromList(
      await _algorithm.decrypt(box, secretKey: _key),
    );
  }
}
