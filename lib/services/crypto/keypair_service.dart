/// Ed25519 signing primitives used to authenticate shared notes.
///
/// The private half of the keypair never leaves [KeypairService] — it lives in
/// the platform keychain and is touched only inside [sign]. Callers receive
/// only the public half via [publicKey] and verifications via [verify].
abstract class KeypairService {
  /// Returns the user's 32-byte Ed25519 public key.
  ///
  /// On first call this generates a fresh keypair, persists the private half
  /// to the platform secure store, and returns the public half. Subsequent
  /// calls return the same bytes for the lifetime of the install.
  Future<List<int>> publicKey();

  /// Signs [bytes] with the user's private key and returns the 64-byte
  /// signature. Generates the keypair on first use, mirroring [publicKey].
  Future<List<int>> sign(List<int> bytes);

  /// Verifies a detached signature against arbitrary [bytes] and a peer's
  /// [publicKey]. Returns false on any malformation; never throws on bad input.
  Future<bool> verify({
    required List<int> bytes,
    required List<int> signature,
    required List<int> publicKey,
  });
}
