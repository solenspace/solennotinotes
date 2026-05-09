import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/crypto/keypair_service.dart';

void main() {
  group('Ed25519 keypair (in-memory)', () {
    // We cannot exercise FlutterSecureKeypairService directly without
    // the platform plugins; instead we cover the contract via an
    // in-memory implementation that uses the same algorithm. This proves
    // the round-trip semantics callers depend on without spinning up the
    // platform channel under flutter_test.
    final service = _InMemoryKeypairService();

    test('publicKey is stable across calls', () async {
      final a = await service.publicKey();
      final b = await service.publicKey();
      expect(a, b);
      expect(a.length, 32);
    });

    test('sign + verify round-trip succeeds', () async {
      final pub = await service.publicKey();
      final msg = Uint8List.fromList(List<int>.generate(256, (i) => i % 256));
      final sig = await service.sign(msg);
      expect(sig.length, 64);
      final ok = await service.verify(bytes: msg, signature: sig, publicKey: pub);
      expect(ok, isTrue);
    });

    test('verify fails for wrong key', () async {
      final wrong = await Ed25519().newKeyPair();
      final wrongPub = (await wrong.extractPublicKey()).bytes;
      final msg = Uint8List.fromList([1, 2, 3, 4]);
      final sig = await service.sign(msg);
      final ok = await service.verify(bytes: msg, signature: sig, publicKey: wrongPub);
      expect(ok, isFalse);
    });

    test('verify fails for tampered payload', () async {
      final pub = await service.publicKey();
      final msg = Uint8List.fromList([1, 2, 3, 4]);
      final sig = await service.sign(msg);
      final tampered = Uint8List.fromList([1, 2, 3, 5]);
      final ok = await service.verify(bytes: tampered, signature: sig, publicKey: pub);
      expect(ok, isFalse);
    });

    test('verify never throws on garbage signature input', () async {
      final pub = await service.publicKey();
      final ok = await service.verify(
        bytes: const [1, 2, 3],
        signature: const [0, 0, 0],
        publicKey: pub,
      );
      expect(ok, isFalse);
    });
  });
}

class _InMemoryKeypairService implements KeypairService {
  _InMemoryKeypairService() : _algorithm = Ed25519();

  final Ed25519 _algorithm;
  Future<SimpleKeyPair>? _cached;

  Future<SimpleKeyPair> _pair() => _cached ??= _algorithm.newKeyPair();

  @override
  Future<List<int>> publicKey() async {
    final p = await _pair();
    final pub = await p.extractPublicKey();
    return pub.bytes;
  }

  @override
  Future<List<int>> sign(List<int> bytes) async {
    final p = await _pair();
    final sig = await _algorithm.sign(bytes, keyPair: p);
    return sig.bytes;
  }

  @override
  Future<bool> verify({
    required List<int> bytes,
    required List<int> signature,
    required List<int> publicKey,
  }) async {
    try {
      return await _algorithm.verify(
        bytes,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }
}
