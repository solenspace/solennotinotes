import 'package:noti_notes_app/services/crypto/keypair_service.dart';

/// Deterministic [KeypairService] for downstream specs (23+ payload codec,
/// inbox attribution).
///
/// Public key is fixed at construction; signatures are simply a hash-style
/// prefix concat of the message and key — enough for verify round-trips in
/// tests but obviously not real crypto.
class FakeKeypairService implements KeypairService {
  FakeKeypairService({List<int>? publicKey})
      : _publicKey = publicKey ?? const <int>[1, 2, 3, 4, 5, 6, 7, 8];

  final List<int> _publicKey;

  @override
  Future<List<int>> publicKey() async => List<int>.unmodifiable(_publicKey);

  @override
  Future<List<int>> sign(List<int> bytes) async {
    return [..._publicKey, ...bytes];
  }

  @override
  Future<bool> verify({
    required List<int> bytes,
    required List<int> signature,
    required List<int> publicKey,
  }) async {
    if (signature.length < publicKey.length) return false;
    for (var i = 0; i < publicKey.length; i++) {
      if (signature[i] != publicKey[i]) return false;
    }
    final tail = signature.sublist(publicKey.length);
    if (tail.length != bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (tail[i] != bytes[i]) return false;
    }
    return true;
  }
}
