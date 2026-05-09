import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'keypair_service.dart';

const _privateKeyStorageKey = 'noti_identity_ed25519_private_v1';

/// Ed25519 [KeypairService] backed by the platform keychain.
///
/// On iOS the private bytes land in the Keychain (kSecClassGenericPassword,
/// `accessibility = first_unlock`). On Android they land in
/// EncryptedSharedPreferences. The public key is derived from the private seed
/// each time it is needed — we never persist the public half separately.
class FlutterSecureKeypairService implements KeypairService {
  FlutterSecureKeypairService({
    FlutterSecureStorage? storage,
    Ed25519? algorithm,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _algorithm = algorithm ?? Ed25519();

  final FlutterSecureStorage _storage;
  final Ed25519 _algorithm;

  Future<SimpleKeyPair>? _cached;

  Future<SimpleKeyPair> _keyPair() {
    return _cached ??= _loadOrGenerate();
  }

  Future<SimpleKeyPair> _loadOrGenerate() async {
    final existing = await _storage.read(key: _privateKeyStorageKey);
    if (existing != null) {
      final seed = base64Decode(existing);
      return _algorithm.newKeyPairFromSeed(seed);
    }
    final fresh = await _algorithm.newKeyPair();
    final seed = await fresh.extractPrivateKeyBytes();
    await _storage.write(
      key: _privateKeyStorageKey,
      value: base64Encode(seed),
    );
    return fresh;
  }

  @override
  Future<List<int>> publicKey() async {
    final pair = await _keyPair();
    final pub = await pair.extractPublicKey();
    return pub.bytes;
  }

  @override
  Future<List<int>> sign(List<int> bytes) async {
    final pair = await _keyPair();
    final signature = await _algorithm.sign(bytes, keyPair: pair);
    return signature.bytes;
  }

  @override
  Future<bool> verify({
    required List<int> bytes,
    required List<int> signature,
    required List<int> publicKey,
  }) async {
    try {
      final ok = await _algorithm.verify(
        bytes,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
      return ok;
    } on Object {
      return false;
    }
  }
}
